import SwiftUI
import SwiftData

/// カレンダーホーム（§6.2）。月/週表示・来店マーカー・連続記録・週次ゴール。
struct CalendarHomeView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        NavigationStack {
            if let uid = auth.currentUserId {
                CalendarHomeContent(userId: uid)
            } else {
                EmptyStateView(systemImage: "person.crop.circle.badge.exclamationmark", title: "未ログイン")
            }
        }
    }
}

private struct CalendarHomeContent: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(LocationService.self) private var location
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(NotificationService.self) private var notifications
    @Query private var visits: [Visit]
    @Query private var workouts: [Workout]
    @Query private var gyms: [Gym]
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal: Int = 3

    @State private var anchor = Date.now
    @State private var selectedDate: SelectedDay?
    @State private var showCheckIn = false
    @State private var editingWorkout: Workout?

    /// navigationDestination(item:) は Identifiable を要求するため Date をラップする。
    private struct SelectedDay: Identifiable, Hashable {
        let date: Date
        var id: Date { date }
    }

    private let calendar = Calendar.current

    init(userId: UUID) {
        self.userId = userId
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId }, sort: \Visit.visitedAt)
        _workouts = Query(filter: #Predicate<Workout> { $0.userId == userId }, sort: \Workout.date)
        _gyms = Query(sort: \Gym.name)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                heroCard
                calendarCard
                upcomingSection
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.bg0)
        .navigationTitle("Gymnee")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showCheckIn = true } label: {
                    Label("チェックイン", systemImage: "camera.fill")
                }
                .tint(Theme.energy)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.profile) { Image(systemName: "person.crop.circle") }
            }
        }
        .fullScreenCover(isPresented: $showCheckIn) { CheckInView() }
        // AppRoute の destination は NavigationStack ルート（ここ）で一括宣言する。
        // push 先（ProfileView 等）の子リンクからも確実に解決できるようにするため
        // （iOS 26.5 では pushed view 上の navigationDestination が無効化される）。
        .gymneeNavigationDestinations(userId: userId)
        .navigationDestination(item: $selectedDate) { selection in
            DayDetailView(userId: userId, date: selection.date, onEditWorkout: { editingWorkout = $0 })
        }
        // ロガーへの遷移はルートで宣言（pushed view 上の navigationDestination は 26.5 で無効のため）。
        .navigationDestination(item: $editingWorkout) { workout in
            WorkoutLoggerView(workout: workout)
        }
        // Watch 保留チェックインの取り込みは「一度だけ」。visits.count トリガに乗せると
        // 挿入→count変化→再実行→再挿入 の無限ループになる（特に App Group 破損時）。
        .task { consumeWatchCheckIns() }
        // Watch から WCSession 経由でチェックインが届いたら、前面表示中でも即取り込む（重複ガード済み）。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeWatchCheckInReceived)) { _ in
            consumeWatchCheckIns()
        }
        .task(id: visits.count) { syncPlatform() }
    }

    /// Widget スナップショット更新＋ジオフェンス監視開始＋通知予約（§6.10）。挿入は行わない。
    private func syncPlatform() {
        SnapshotUpdater.update(userId: userId, context: context)
        let regions = gyms.compactMap { gym -> (id: UUID, name: String, lat: Double, lng: Double)? in
            guard let lat = gym.lat, let lng = gym.lng else { return nil }
            return (gym.id, gym.name, lat, lng)
        }
        location.startMonitoring(gymRegions: regions)
        scheduleReminders()
    }

    private func scheduleReminders() {
        #if DEBUG
        // デモ/スクショ用ハーネス起動時は許諾ダイアログを出さない（自動撮影をクリーンに保つ）。
        if !DebugSupport.demoRequested { Task { await notifications.requestAuthorization() } }
        #else
        Task { await notifications.requestAuthorization() }
        #endif
        let today = calendar.startOfDay(for: .now)
        let checkedInToday = visits.contains { calendar.isDateInToday($0.visitedAt) }
        notifications.scheduleStreakReminder(streak: currentStreak, hasCheckedInToday: checkedInToday)
        let planned = workouts
            .filter { $0.isPlanned && $0.completedAt == nil && $0.date >= today }
            .map { (id: $0.id, name: $0.name, date: $0.date) }
        notifications.schedulePlannedWorkouts(planned)
    }

    /// Watch（App Group キュー）からのクイックチェックインを来店として取り込む。
    private func consumeWatchCheckIns() {
        let pending = SharedStore.consumePendingCheckIns()
        guard !pending.isEmpty else { return }
        let gym = gyms.first(where: { $0.isFavorite }) ?? gyms.first
        var insertedVisits: [Visit] = []
        for date in pending {
            // 既に同時刻の来店があれば重複挿入しない（App Group 破損でキューが消えない場合の保険）。
            if visits.contains(where: { abs($0.visitedAt.timeIntervalSince(date)) < 1 }) { continue }
            let visit = Visit(userId: userId, visitedAt: date, gym: gym)
            context.insert(visit)
            insertedVisits.append(visit)
        }
        if !insertedVisits.isEmpty {
            try? context.save()
            for visit in insertedVisits {
                sync.enqueue(PendingChange(entity: "visits", recordId: visit.id, operation: .upsert, updatedAt: visit.updatedAt))
            }
        }
    }

    // MARK: - Hero (streak ring + week goal + plain language)

    private var heroCard: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.xl) {
                ProgressRing(progress: goalProgress, lineWidth: 11, size: 108) {
                    VStack(spacing: 0) {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(currentStreak > 0 ? Theme.warning : Theme.textTertiary)
                        Text("\(currentStreak)")
                            .font(.numL)
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        Text("連続日")
                            .font(.overline)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        OverlineLabel(text: "今週の達成")
                        Spacer()
                        if weekCount >= weeklyGoal {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.lime)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(weekCount)")
                            .font(.numL)
                            .foregroundStyle(weekCount >= weeklyGoal ? Theme.lime : Theme.textPrimary)
                            .contentTransition(.numericText())
                        Text("/ \(weeklyGoal)")
                            .font(.numS)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    weekDots
                }
            }

            Divider().overlay(Theme.bg3)

            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: encouragement.icon)
                    .foregroundStyle(Theme.lime)
                Text(encouragement.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
        }
        .gymneeCard(padding: Theme.Spacing.xl, highlighted: weekCount >= weeklyGoal)
    }

    /// 週次ゴールの達成ドット（埋まると lime）。
    private var weekDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(weeklyGoal, 1), id: \.self) { i in
                Capsule()
                    .fill(i < weekCount ? Theme.lime : Theme.bg3)
                    .frame(height: 6)
            }
        }
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            header
            weekdayHeader
            grid
            legend
        }
        .gymneeCard()
    }

    private var header: some View {
        HStack {
            Button { withAnimation(.snappy) { shift(-1) } } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
            }
            Spacer()
            Text(titleText).font(.headline)
            if !calendar.isDate(anchor, equalTo: .now, toGranularity: .month) {
                Button { withAnimation(.snappy) { anchor = .now } } label: {
                    Text("今日")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(Theme.limeSoft, in: Capsule())
                        .foregroundStyle(Theme.lime)
                }
                .padding(.leading, 4)
            }
            Spacer()
            Button { withAnimation(.snappy) { shift(1) } } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold))
            }
        }
        .tint(Theme.textPrimary)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textTertiary).frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        // Set は 42 セルで使い回す（セル毎の再生成＝O(visits)×42 を回避）。
        let vDays = visitDays
        let wDays = workoutDays
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(displayedDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, visitDays: vDays, workoutDays: wDays)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    private func dayCell(_ date: Date, visitDays: Set<Date>, workoutDays: Set<Date>) -> some View {
        let start = calendar.startOfDay(for: date)
        let hasVisit = visitDays.contains(start)
        let hasWorkout = workoutDays.contains(start)
        let isToday = calendar.isDateInToday(date)
        let inMonth = calendar.isDate(date, equalTo: anchor, toGranularity: .month)
        return Button {
            selectedDate = SelectedDay(date: start)
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Theme.onLime : (inMonth ? Theme.textPrimary : Theme.textTertiary))
                    .frame(width: 30, height: 30)
                    .background {
                        if isToday {
                            Circle().fill(Theme.limeFill)
                        } else if hasVisit {
                            Circle().fill(Theme.limeSoft)
                        }
                    }
                HStack(spacing: 3) {
                    Circle().fill(hasVisit && !isToday ? Theme.lime : .clear).frame(width: 5, height: 5)
                    Circle().fill(hasWorkout ? Theme.warning : .clear).frame(width: 5, height: 5)
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.lg) {
            legendItem(color: Theme.lime, label: "来店")
            legendItem(color: Theme.warning, label: "ワークアウト")
            Spacer()
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Upcoming (予定→実績)

    private var upcomingSection: some View {
        let planned = workouts.filter { $0.isPlanned && $0.completedAt == nil && $0.date >= calendar.startOfDay(for: .now) }
            .sorted { $0.date < $1.date }
            .prefix(3)
        return Group {
            if !planned.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SectionHeader(title: "これからの予定")
                    ForEach(Array(planned), id: \.id) { w in
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(Theme.warning)
                                .frame(width: 36, height: 36)
                                .background(Theme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                            Text(w.name).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(w.date, format: .dateTime.month().day())
                                .font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .gymneeCard()
            }
        }
    }

    // MARK: - Derived data

    private var visitDays: Set<Date> {
        Set(visits.map { calendar.startOfDay(for: $0.visitedAt) })
    }
    private var workoutDays: Set<Date> {
        Set(workouts.filter { $0.completedAt != nil || !$0.isPlanned }.map { calendar.startOfDay(for: $0.date) })
    }
    private var currentStreak: Int {
        StreakCalculator.currentStreak(visitDays: visits.map(\.visitedAt), calendar: calendar)
    }
    private var longestStreak: Int {
        StreakCalculator.longestStreak(visitDays: visits.map(\.visitedAt), calendar: calendar)
    }
    private var weekCount: Int {
        StreakCalculator.weeklyVisitDays(visitDays: visits.map(\.visitedAt), calendar: calendar)
    }
    private var goalProgress: Double {
        guard weeklyGoal > 0 else { return 0 }
        return min(1, Double(weekCount) / Double(weeklyGoal))
    }

    /// 励まし文（Gentler Streak 流：責めない・前向き）。
    private var encouragement: (icon: String, text: String) {
        if weekCount >= weeklyGoal {
            return ("checkmark.seal.fill", "今週は\(weekCount)日トレ — 目標達成、最高の週！")
        }
        if currentStreak >= 3 {
            return ("flame.fill", "\(currentStreak)日連続。この調子で続けよう。")
        }
        if weekCount > 0 {
            return ("bolt.fill", "今週は\(weekCount)日。あと\(weeklyGoal - weekCount)日で目標達成。")
        }
        return ("sparkles", "新しい週。まずは1回チェックインしてみよう。")
    }

    private var weekdaySymbols: [String] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        return f.veryShortStandaloneWeekdaySymbols
    }

    private var titleText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年 M月"
        return f.string(from: anchor)
    }

    /// 表示対象の日配列。前後の空白を nil で埋めた当月のグリッド。
    private var displayedDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: anchor) else { return [] }
        let firstDay = monthInterval.start
        let weekdayOfFirst = calendar.component(.weekday, from: firstDay)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 30
        var result: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<daysInMonth {
            result.append(calendar.date(byAdding: .day, value: d, to: firstDay))
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private func shift(_ direction: Int) {
        if let next = calendar.date(byAdding: .month, value: direction, to: anchor) {
            anchor = next
        }
    }
}
