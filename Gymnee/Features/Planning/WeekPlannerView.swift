import SwiftUI
import SwiftData

/// ワークアウト計画（§6.5）。今後7日間に、Apple/Google カレンダーの予定とワークアウト計画を重ねて表示。
/// 予定を見ながら手動で配置・移動でき、AI計画（Premium）で自動提案も行う（8c）。
struct WeekPlannerView: View {
    let userId: UUID
    /// 計画を「開始」して実記録を作成→ロガーを開く（遷移はルート＝WorkoutHome側に委ねる）。
    var onStart: (Workout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(CalendarService.self) private var calendarService
    @Environment(GoogleCalendarService.self) private var googleCalendar
    @Environment(SubscriptionService.self) private var subscription
    @Environment(AuthService.self) private var auth
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal: Int = 3
    @Query private var planned: [PlannedWorkout]
    @Query private var routines: [Routine]
    @Query private var recentWorkouts: [Workout]

    @State private var addDay: PlanDay?
    // 計画追加の下書き選択（保存するまで永続化しない）。
    @State private var planDraftTitle: String?
    @State private var planDraftRoutineId: UUID?
    @State private var showPaywall = false
    @AppStorage("gymnee.aiFreeUsed") private var aiFreeUsed = false
    @State private var aiInfo = false
    @State private var aiRunning = false
    /// カレンダー予定のキャッシュ（startOfDay→予定）。body 毎の同期列挙(hang)を避けるため一度だけ取得。
    @State private var eventsByDay: [Date: [CalendarEvent]] = [:]

    init(userId: UUID, onStart: @escaping (Workout) -> Void = { _ in }) {
        self.userId = userId
        self.onStart = onStart
        _planned = Query(filter: #Predicate<PlannedWorkout> { $0.userId == userId }, sort: \PlannedWorkout.date)
        _routines = Query(filter: #Predicate<Routine> { $0.userId == userId }, sort: \Routine.name)
        let since = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        _recentWorkouts = Query(
            filter: #Predicate<Workout> { $0.userId == userId && $0.completedAt != nil && $0.date >= since },
            sort: \Workout.date, order: .reverse
        )
    }

    private struct PlanDay: Identifiable { let date: Date; var id: Double { date.timeIntervalSince1970 } }

    private let cal = Calendar.current
    private var days: [Date] {
        let start = cal.startOfDay(for: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekPlans: [PlannedWorkout] {
        let set = Set(days.map { cal.startOfDay(for: $0) })
        return planned.filter { set.contains(cal.startOfDay(for: $0.date)) }
    }

    var body: some View {
        List {
            if !weekPlans.isEmpty {
                Section {
                    let done = weekPlans.filter(\.isDone).count
                    let total = weekPlans.count
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack {
                            Text("今週の計画達成").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(done)/\(total)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.lime)
                        }
                        ProgressView(value: Double(done), total: Double(max(total, 1))).tint(Theme.lime)
                    }
                }
            }
            if !calendarService.authorized {
                Section {
                    Button { Task { await calendarService.requestAccess(); await loadEvents() } } label: {
                        Label("Apple カレンダーと連携", systemImage: "calendar.badge.plus")
                    }
                } footer: {
                    Text("予定を読み込み、空いている日に合わせて計画できます。")
                }
            }
            ForEach(days, id: \.self) { day in
                Section(day.formatted(.dateTime.month().day().weekday(.abbreviated))) {
                    ForEach(events(on: day)) { ev in
                        Label {
                            HStack {
                                Text(ev.title).lineLimit(1)
                                Spacer()
                                Text(ev.isAllDay ? "終日" : ev.start.formatted(date: .omitted, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: ev.source == .google ? "calendar.circle.fill" : "calendar")
                                .foregroundStyle(ev.source == .google ? Theme.lime : .secondary)
                        }
                    }
                    ForEach(plannedItems(on: day)) { p in
                        plannedRow(p)
                    }
                    Button { addDay = PlanDay(date: day) } label: {
                        Label("ワークアウトを計画", systemImage: "plus.circle").font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("計画")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadEvents() }
        .onChange(of: calendarService.authorized) { _, _ in Task { await loadEvents() } }
        .onChange(of: calendarService.isEnabled) { _, _ in Task { await loadEvents() } }
        .onChange(of: googleCalendar.isConnected) { _, _ in Task { await loadEvents() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if aiRunning {
                    ProgressView()
                } else {
                    Button { aiPlan() } label: { Label("AIで計画", systemImage: "sparkles") }
                }
            }
        }
        .sheet(item: $addDay) { day in addSheet(day.date) }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert("AIワークアウト計画", isPresented: $aiInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("予定を避けて今週のメニューを自動で組み替えます。現在 Gemini 連携を準備中です（まもなく有効化）。")
        }
    }

    // MARK: - Rows

    private func plannedRow(_ p: PlannedWorkout) -> some View {
        HStack {
            Button {
                p.isDone.toggle(); p.updatedAt = .now; try? context.save()
            } label: {
                Image(systemName: p.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(p.isDone ? Theme.lime : .secondary)
            }
            .buttonStyle(.plain)
            Text(p.title).strikethrough(p.isDone).foregroundStyle(p.isDone ? .secondary : .primary)
            Spacer()
            // 計画の開始は「今日」のみ。過去/未来は閲覧・チェック・移動のみ。
            if cal.isDateInToday(p.date) {
                Button { start(p) } label: {
                    Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(Theme.lime)
                }
                .buttonStyle(.plain)
            }
            Menu {
                Menu("別の日へ移動") {
                    ForEach(days, id: \.self) { d in
                        Button(d.formatted(.dateTime.month().day().weekday(.abbreviated))) {
                            p.date = d; p.updatedAt = .now; try? context.save()
                        }
                    }
                }
                Button("削除", role: .destructive) { context.delete(p); try? context.save() }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Add sheet

    /// 行タップは「選択」のみ。右上「保存」を押すまで永続化しない。
    private func addSheet(_ day: Date) -> some View {
        NavigationStack {
            List {
                Section("カスタムセットから") {
                    if routines.isEmpty {
                        Text("カスタムセット未作成").foregroundStyle(.secondary)
                    }
                    ForEach(routines) { r in
                        planSelectRow(title: r.name, routineId: r.id)
                    }
                }
                Section("自由入力") {
                    ForEach(["胸の日", "背中の日", "脚の日", "肩・腕", "有酸素", "休養"], id: \.self) { t in
                        planSelectRow(title: t, routineId: nil)
                    }
                }
            }
            .navigationTitle(day.formatted(.dateTime.month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { closeAdd() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { savePlan(on: day) }.bold().disabled(planDraftTitle == nil)
                }
            }
            .interactiveDismissDisabled()
        }
        .presentationDetents([.medium, .large])
    }

    /// 計画追加シートの選択行（タップで選択、チェックマーク表示。保存まで永続化しない）。
    @ViewBuilder
    private func planSelectRow(title: String, routineId: UUID?) -> some View {
        let isSelected = planDraftRoutineId == routineId && planDraftTitle == title
        Button {
            planDraftTitle = title
            planDraftRoutineId = routineId
        } label: {
            HStack {
                Text(title).foregroundStyle(Theme.textPrimary)
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(Theme.lime) }
            }
        }
    }

    // MARK: - Helpers

    private func events(on day: Date) -> [CalendarEvent] {
        eventsByDay[cal.startOfDay(for: day)] ?? []
    }

    /// 週分の予定（Apple＋Google）を取得して startOfDay 単位にキャッシュ（body 内の同期列挙を排除）。
    private func loadEvents() async {
        guard let first = days.first, let last = days.last,
              let end = cal.date(byAdding: .day, value: 1, to: last) else { eventsByDay = [:]; return }
        var all: [CalendarEvent] = []
        if calendarService.isActive { all += calendarService.calendarEvents(from: first, to: end) }
        if googleCalendar.isConnected { all += await googleCalendar.events(from: first, to: end) }
        eventsByDay = Dictionary(grouping: all) { cal.startOfDay(for: $0.start) }
    }

    private func plannedItems(on day: Date) -> [PlannedWorkout] {
        planned.filter { cal.isDate($0.date, inSameDayAs: day) }
    }

    /// 「保存」押下時のみ永続化。下書き選択をクリアしてシートを閉じる。
    private func savePlan(on day: Date) {
        guard let title = planDraftTitle else { return }
        add(title: title, routineId: planDraftRoutineId, on: day)
        planDraftTitle = nil
        planDraftRoutineId = nil
    }

    /// シートを閉じて下書き選択を破棄（保存せず）。
    private func closeAdd() {
        addDay = nil
        planDraftTitle = nil
        planDraftRoutineId = nil
    }

    private func add(title: String, routineId: UUID?, on day: Date) {
        let p = PlannedWorkout(userId: userId, date: day, title: title, routineId: routineId)
        context.insert(p)
        try? context.save()
        addDay = nil
        // 計画作成時に Google カレンダーへ終日予定として自動追加（連携中のみ）。
        if googleCalendar.isConnected {
            let start = cal.startOfDay(for: day)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            Task { await googleCalendar.addEvent(title: "Gymnee: \(title)", start: start, end: end, allDay: true) }
        }
    }

    /// 計画を「開始」：共通ロジックで実記録を作成し（AI詳細→ルーティン→空）ロガーを開く。
    private func start(_ plan: PlannedWorkout) {
        onStart(PlanStarter.start(plan, userId: userId, routines: routines, context: context))
    }

    private func aiPlan() {
        // 初回は無料で体験 → 価値を感じてから課金（無料ユーザーは2回目以降 Paywall）。
        if !subscription.isPremium {
            if aiFreeUsed { showPaywall = true; return }
            aiFreeUsed = true
        }
        aiRunning = true
        Task {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.calendar = cal
            fmt.locale = Locale(identifier: "en_US_POSIX")
            let dayStrings = days.map { fmt.string(from: $0) }
            let routineNames = routines.map(\.name)
            let evs: [[String: Any]] = days.flatMap { d in
                events(on: d).map { ev in
                    ["title": ev.title, "date": fmt.string(from: ev.start), "allDay": ev.isAllDay]
                }
            }
            let history = buildHistory(formatter: fmt)
            let recovery = buildRecovery()
            let result = await auth.planWorkouts(days: dayStrings, routines: routineNames, weeklyGoal: weeklyGoal, events: evs, history: history, recovery: recovery)
            aiRunning = false
            if let result, !result.isEmpty {
                applyPlan(result, formatter: fmt)
            } else {
                aiInfo = true   // キー未設定/失敗時は「準備中」案内
            }
        }
    }

    /// AI が返した計画で、今週分の計画を置き換える。
    private func applyPlan(_ items: [SupabaseClient.PlanItem], formatter: DateFormatter) {
        for p in planned where days.contains(where: { cal.isDate($0, inSameDayAs: p.date) }) {
            context.delete(p)
        }
        for item in items {
            guard let date = formatter.date(from: item.date),
                  days.contains(where: { cal.isDate($0, inSameDayAs: date) }) else { continue }
            let plan = PlannedWorkout(userId: userId, date: cal.startOfDay(for: date), title: item.title)
            if !item.exercises.isEmpty, let data = try? JSONEncoder().encode(item.exercises) {
                plan.detailJSON = String(data: data, encoding: .utf8)
            }
            context.insert(plan)
        }
        try? context.save()
    }

    /// 部位ごとの回復状況を AI 用に要約（RecoveryAnalyzer）。連日同部位を避ける根拠にする。
    private func buildRecovery() -> [[String: Any]] {
        var lastTrained: [MuscleGroup: Date] = [:]
        for w in recentWorkouts where w.completedAt != nil {
            for we in w.exercises where !we.sets.isEmpty {
                guard let mg = we.exercise?.muscleGroup else { continue }
                let d = w.completedAt ?? w.date
                if let e = lastTrained[mg] { lastTrained[mg] = max(e, d) } else { lastTrained[mg] = d }
            }
        }
        return RecoveryAnalyzer.statuses(lastTrained: lastTrained).map { s in
            ["muscle": s.muscle.rawValue,
             "hoursSince": Int(s.hoursSince ?? 9999),
             "recovered": s.isRecovered]
        }
    }

    /// 直近4週間の記録を AI 用に要約（種目・部位・トップセットの重量/レップ）。
    private func buildHistory(formatter: DateFormatter) -> [[String: Any]] {
        recentWorkouts.prefix(20).map { w in
            [
                "date": formatter.string(from: w.date),
                "exercises": w.exercises.compactMap { we -> [String: Any]? in
                    guard let ex = we.exercise else { return nil }
                    let top = we.sets.max(by: { $0.weight < $1.weight })
                    return ["name": ex.name, "muscleGroup": ex.muscleGroupRaw,
                            "weight": top?.weight ?? 0, "reps": top?.reps ?? 0]
                },
            ]
        }
    }
}
