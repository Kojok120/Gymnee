import SwiftUI
import SwiftData

/// 日別詳細（§5 Day Detail）。その日の計画・来店・ワークアウト一覧。
struct DayDetailView: View {
    let userId: UUID
    let date: Date
    /// ワークアウト編集を開く。pushed view 上では navigationDestination が無効(iOS26.5)なため、
    /// ロガーへの遷移はルート(CalendarHomeContent)側に委ねる。
    var onEditWorkout: (Workout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Query private var visits: [Visit]
    @Query private var workouts: [Workout]
    @Query private var planned: [PlannedWorkout]
    @Query private var routines: [Routine]
    @State private var showAddVisit = false

    private let calendar = Calendar.current

    init(userId: UUID, date: Date, onEditWorkout: @escaping (Workout) -> Void = { _ in }) {
        self.userId = userId
        self.date = date
        self.onEditWorkout = onEditWorkout
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _visits = Query(
            filter: #Predicate<Visit> { $0.userId == userId && $0.visitedAt >= start && $0.visitedAt < end },
            sort: \Visit.visitedAt, order: .reverse
        )
        _workouts = Query(
            filter: #Predicate<Workout> { $0.userId == userId && $0.date >= start && $0.date < end },
            sort: \Workout.date, order: .reverse
        )
        _planned = Query(
            filter: #Predicate<PlannedWorkout> { $0.userId == userId && !$0.isDone && $0.date >= start && $0.date < end },
            sort: \PlannedWorkout.date
        )
        _routines = Query(filter: #Predicate<Routine> { $0.userId == userId }, sort: \Routine.name)
    }

    var body: some View {
        List {
            if !planned.isEmpty {
                Section("計画") {
                    ForEach(planned) { plan in
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "calendar.badge.clock").foregroundStyle(Theme.lime)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.title).font(.subheadline.weight(.semibold))
                                    .lineLimit(1).truncationMode(.tail)
                                if let n = planExerciseCount(plan) {
                                    Text("\(n)種目").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("開始") { startPlan(plan) }
                                .buttonStyle(.borderedProminent).tint(Theme.lime).controlSize(.small)
                        }
                        .swipeActions {
                            Button("削除", role: .destructive) { deletePlan(plan) }
                        }
                    }
                }
            }

            Section("来店") {
                if visits.isEmpty {
                    Text("来店記録なし").foregroundStyle(.secondary)
                } else {
                    ForEach(visits) { visit in
                        VisitRow(visit: visit)
                            .swipeActions {
                                Button("削除", role: .destructive) { delete(visit) }
                            }
                    }
                }
                Button { showAddVisit = true } label: {
                    Label("この日に来店を追加", systemImage: "plus.circle")
                }
            }

            Section("ワークアウト") {
                if workouts.isEmpty {
                    Text("ワークアウト記録なし").foregroundStyle(.secondary)
                } else {
                    ForEach(workouts) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            WorkoutRow(workout: workout)
                        }
                        .swipeActions {
                            Button("削除", role: .destructive) { deleteWorkout(workout) }
                        }
                    }
                }
                Button { addWorkout() } label: {
                    Label("この日にワークアウトを追加", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddVisit) {
            GymPickerView(userId: userId) { gym in
                addVisit(gym: gym)
                showAddVisit = false
            }
        }
    }

    /// その日に来店を追加（ジムを選択して作成）。過去/未来の後追い記録に。
    private func addVisit(gym: Gym) {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let visit = Visit(userId: userId, visitedAt: noon, gym: gym)
        context.insert(visit)
        try? context.save()
        // FK 担保のため参照先ジムも送出してから来店を送る。
        sync.enqueue(PendingChange(entity: "gyms", recordId: gym.id, operation: .upsert, updatedAt: .now))
        sync.enqueue(PendingChange(entity: "visits", recordId: visit.id, operation: .upsert, updatedAt: visit.updatedAt))
    }

    /// その日（過去でも未来でも）にワークアウトを新規作成してロガーを開く。記録の後追い入力・先取り計画に。
    private func addWorkout() {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let workout = Workout(userId: userId, date: noon, name: "ワークアウト")
        context.insert(workout)
        try? context.save()
        onEditWorkout(workout)
    }

    /// 計画を開始＝実記録に変えてロガーを開く。
    private func startPlan(_ plan: PlannedWorkout) {
        let workout = PlanStarter.start(plan, userId: userId, routines: routines, context: context)
        onEditWorkout(workout)
    }

    private func planExerciseCount(_ plan: PlannedWorkout) -> Int? {
        guard let json = plan.detailJSON, let data = json.data(using: .utf8),
              let exs = try? JSONDecoder().decode([SupabaseClient.PlanExercise].self, from: data), !exs.isEmpty
        else { return nil }
        return exs.count
    }

    private func deletePlan(_ plan: PlannedWorkout) {
        context.delete(plan) // PlannedWorkout は端末ローカルのみ（同期対象外）
        try? context.save()
    }

    private var titleText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E)"
        return f.string(from: date)
    }

    private func delete(_ visit: Visit) {
        let visitId = visit.id
        PhotoStore.delete(visit.localPhotoFilename)
        context.delete(visit)
        try? context.save()
        sync.enqueue(PendingChange(entity: "visits", recordId: visitId, operation: .delete, updatedAt: .now))
    }

    private func deleteWorkout(_ workout: Workout) {
        let id = workout.id
        context.delete(workout) // 配下の workout_exercises / exercise_sets は cascade で削除
        try? context.save()
        sync.enqueue(PendingChange(entity: "workouts", recordId: id, operation: .delete, updatedAt: .now))
    }
}
