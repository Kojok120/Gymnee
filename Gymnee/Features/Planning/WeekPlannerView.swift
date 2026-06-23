import SwiftUI
import SwiftData
import EventKit

/// ワークアウト計画（§6.5）。今後7日間に、Apple カレンダーの予定とワークアウト計画を重ねて表示。
/// 予定を見ながら手動で配置・移動でき、AI計画（Premium）で自動提案も行う（8c）。
struct WeekPlannerView: View {
    let userId: UUID
    /// 計画を「開始」して実記録を作成→ロガーを開く（遷移はルート＝WorkoutHome側に委ねる）。
    var onStart: (Workout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(CalendarService.self) private var calendarService
    @Environment(SubscriptionService.self) private var subscription
    @Environment(AuthService.self) private var auth
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal: Int = 3
    @Query private var planned: [PlannedWorkout]
    @Query private var routines: [Routine]

    @State private var addDay: PlanDay?
    @State private var showPaywall = false
    @State private var aiInfo = false
    @State private var aiRunning = false

    init(userId: UUID, onStart: @escaping (Workout) -> Void = { _ in }) {
        self.userId = userId
        self.onStart = onStart
        _planned = Query(filter: #Predicate<PlannedWorkout> { $0.userId == userId }, sort: \PlannedWorkout.date)
        _routines = Query(filter: #Predicate<Routine> { $0.userId == userId }, sort: \Routine.name)
    }

    private struct PlanDay: Identifiable { let date: Date; var id: Double { date.timeIntervalSince1970 } }

    private let cal = Calendar.current
    private var days: [Date] {
        let start = cal.startOfDay(for: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        List {
            if !calendarService.authorized {
                Section {
                    Button { Task { await calendarService.requestAccess() } } label: {
                        Label("Apple カレンダーと連携", systemImage: "calendar.badge.plus")
                    }
                } footer: {
                    Text("予定を読み込み、空いている日に合わせて計画できます。")
                }
            }
            ForEach(days, id: \.self) { day in
                Section(day.formatted(.dateTime.month().day().weekday(.abbreviated))) {
                    ForEach(events(on: day), id: \.0) { _, ev in
                        Label {
                            HStack {
                                Text(ev.title ?? "予定").lineLimit(1)
                                Spacer()
                                Text(ev.isAllDay ? "終日" : ev.startDate.formatted(date: .omitted, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "calendar").foregroundStyle(.secondary)
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
            Button { start(p) } label: {
                Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(Theme.lime)
            }
            .buttonStyle(.plain)
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

    private func addSheet(_ day: Date) -> some View {
        NavigationStack {
            List {
                Section("ルーティンから") {
                    if routines.isEmpty {
                        Text("ルーティン未作成").foregroundStyle(.secondary)
                    }
                    ForEach(routines) { r in
                        Button(r.name) { add(title: r.name, routineId: r.id, on: day) }
                    }
                }
                Section("自由入力") {
                    ForEach(["胸の日", "背中の日", "脚の日", "肩・腕", "有酸素", "休養"], id: \.self) { t in
                        Button(t) { add(title: t, routineId: nil, on: day) }
                    }
                }
            }
            .navigationTitle(day.formatted(.dateTime.month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("閉じる") { addDay = nil } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Helpers

    private func events(on day: Date) -> [(Int, EKEvent)] {
        let end = cal.date(byAdding: .day, value: 1, to: day) ?? day
        return Array(calendarService.events(from: day, to: end).enumerated())
    }

    private func plannedItems(on day: Date) -> [PlannedWorkout] {
        planned.filter { cal.isDate($0.date, inSameDayAs: day) }
    }

    private func add(title: String, routineId: UUID?, on day: Date) {
        let p = PlannedWorkout(userId: userId, date: day, title: title, routineId: routineId)
        context.insert(p)
        try? context.save()
        addDay = nil
    }

    /// 計画を「開始」：実記録(Workout)を今この瞬間で作成し、ルーティン紐付きなら種目/前回値を引き継いで
    /// プリフィル。計画は完了扱いにしてロガーを開く。
    private func start(_ plan: PlannedWorkout) {
        let workout = Workout(userId: userId, date: .now, name: plan.title, routineId: plan.routineId)
        context.insert(workout)
        if let rid = plan.routineId, let routine = routines.first(where: { $0.id == rid }) {
            let ordered = routine.routineExercises.sorted { $0.orderIndex < $1.orderIndex }
            for (i, re) in ordered.enumerated() {
                guard let exercise = re.exercise else { continue }
                let we = WorkoutExercise(orderIndex: i, restSeconds: re.restSeconds, workout: workout, exercise: exercise)
                context.insert(we)
                let prev = WorkoutMetrics.previousSets(for: exercise, userId: userId, excludingWorkoutId: workout.id)
                let setCount = max(re.targetSets, prev.count)
                for s in 0..<setCount {
                    let p = s < prev.count ? prev[s] : nil
                    context.insert(ExerciseSet(setIndex: s, weight: p?.weight ?? 0, reps: p?.reps ?? 0, type: p?.type ?? .normal, workoutExercise: we))
                }
            }
        }
        plan.isDone = true
        plan.updatedAt = .now
        try? context.save()
        onStart(workout)
    }

    private func aiPlan() {
        guard subscription.isPremium else { showPaywall = true; return }
        aiRunning = true
        Task {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.calendar = cal
            fmt.locale = Locale(identifier: "en_US_POSIX")
            let dayStrings = days.map { fmt.string(from: $0) }
            let routineNames = routines.map(\.name)
            let evs: [[String: Any]] = days.flatMap { d in
                events(on: d).map { _, ev in
                    ["title": ev.title ?? "予定", "date": fmt.string(from: ev.startDate), "allDay": ev.isAllDay]
                }
            }
            let result = await auth.planWorkouts(days: dayStrings, routines: routineNames, weeklyGoal: weeklyGoal, events: evs)
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
            context.insert(PlannedWorkout(userId: userId, date: cal.startOfDay(for: date), title: item.title))
        }
        try? context.save()
    }
}
