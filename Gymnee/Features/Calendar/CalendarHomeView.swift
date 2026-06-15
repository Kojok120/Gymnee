import SwiftUI
import SwiftData

/// カレンダーホーム（§6.2）。月/週表示・来店マーカー・連続記録・週次ゴール。
/// ヒートマップ（年間ビュー）とリカバリーは P4 で追加する。
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
    @Query private var visits: [Visit]
    @Query private var workouts: [Workout]
    @Query private var gyms: [Gym]
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal: Int = 3

    @State private var anchor = Date.now
    @State private var isWeekMode = false
    @State private var selectedDate: SelectedDay?

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
                statsRow
                modePicker
                calendarCard
                upcomingSection
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("Gymnee")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    GymListView(userId: userId)
                } label: {
                    Image(systemName: "building.2")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { ProfileView(userId: userId) } label: { Image(systemName: "person.crop.circle") }
            }
        }
        .navigationDestination(item: $selectedDate) { selection in
            DayDetailView(userId: userId, date: selection.date)
        }
        .task(id: visits.count) { syncPlatform() }
    }

    /// Widget スナップショット更新＋ジオフェンス監視開始＋Watch保留チェックイン消化（§6.10）。
    private func syncPlatform() {
        consumeWatchCheckIns()
        SnapshotUpdater.update(userId: userId, context: context)
        let regions = gyms.compactMap { gym -> (id: UUID, name: String, lat: Double, lng: Double)? in
            guard let lat = gym.lat, let lng = gym.lng else { return nil }
            return (gym.id, gym.name, lat, lng)
        }
        location.startMonitoring(gymRegions: regions)
    }

    /// Watch（App Group キュー）からのクイックチェックインを来店として取り込む。
    private func consumeWatchCheckIns() {
        let pending = SharedStore.consumePendingCheckIns()
        guard !pending.isEmpty else { return }
        let gym = gyms.first(where: { $0.isFavorite }) ?? gyms.first
        for date in pending {
            let visit = Visit(userId: userId, visitedAt: date, gym: gym)
            context.insert(visit)
        }
        try? context.save()
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            StatPill(value: "\(currentStreak)", label: "連続日数", tint: .orange)
            StatPill(value: "\(weekCount)/\(weeklyGoal)", label: "今週", tint: weekCount >= weeklyGoal ? Theme.energy : .primary)
            StatPill(value: "\(longestStreak)", label: "最長連続")
        }
    }

    private var modePicker: some View {
        Picker("", selection: $isWeekMode) {
            Text("月").tag(false)
            Text("週").tag(true)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            header
            weekdayHeader
            grid
        }
        .gymneeCard()
    }

    private var header: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(titleText).font(.headline)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
        }
        .overlay(alignment: .trailing) {
            if !calendar.isDate(anchor, equalTo: .now, toGranularity: isWeekMode ? .weekOfYear : .month) {
                Button("今日") { anchor = .now }
                    .font(.caption)
                    .offset(y: 30)
            }
        }
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(displayedDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let start = calendar.startOfDay(for: date)
        let hasVisit = visitDays.contains(start)
        let hasWorkout = workoutDays.contains(start)
        let isToday = calendar.isDateInToday(date)
        return Button {
            selectedDate = SelectedDay(date: start)
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline)
                    .foregroundStyle(calendar.isDate(date, equalTo: anchor, toGranularity: .month) || isWeekMode ? .primary : .secondary)
                HStack(spacing: 2) {
                    Circle().fill(hasVisit ? Theme.energy : .clear).frame(width: 5, height: 5)
                    Circle().fill(hasWorkout ? Color.orange : .clear).frame(width: 5, height: 5)
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isToday ? Theme.energy.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm).stroke(Theme.energy, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Upcoming (予定→実績)

    private var upcomingSection: some View {
        let planned = workouts.filter { $0.isPlanned && $0.completedAt == nil && $0.date >= calendar.startOfDay(for: .now) }
            .sorted { $0.date < $1.date }
            .prefix(3)
        return Group {
            if !planned.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: "予定")
                    ForEach(Array(planned), id: \.id) { w in
                        HStack {
                            Image(systemName: "calendar.badge.clock").foregroundStyle(.orange)
                            Text(w.name)
                            Spacer()
                            Text(w.date, format: .dateTime.month().day())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
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

    private var weekdaySymbols: [String] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        return f.veryShortStandaloneWeekdaySymbols
    }

    private var titleText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = isWeekMode ? "yyyy年 M月" : "yyyy年 M月"
        return f.string(from: anchor)
    }

    /// 表示対象の日配列。月モードは前後の空白を nil で埋める。週モードはその週の7日。
    private var displayedDays: [Date?] {
        if isWeekMode {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: anchor) else { return [] }
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
        } else {
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
    }

    private func shift(_ direction: Int) {
        let component: Calendar.Component = isWeekMode ? .weekOfYear : .month
        if let next = calendar.date(byAdding: component, value: direction, to: anchor) {
            anchor = next
        }
    }
}
