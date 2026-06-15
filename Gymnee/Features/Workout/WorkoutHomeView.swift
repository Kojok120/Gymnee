import SwiftUI
import SwiftData

/// ワークアウトのハブ（§6.5）。空 or ルーティンから開始、最近の記録、ルーティン/種目/プレートへの導線。
struct WorkoutHomeView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        NavigationStack {
            if let uid = auth.currentUserId {
                WorkoutHomeContent(userId: uid)
            } else {
                EmptyStateView(systemImage: "person.crop.circle.badge.exclamationmark", title: "未ログイン")
            }
        }
    }
}

private struct WorkoutHomeContent: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Query private var routines: [Routine]
    @Query private var recentWorkouts: [Workout]
    @State private var activeWorkout: Workout?
    @State private var showPlateCalc = false

    init(userId: UUID) {
        self.userId = userId
        _routines = Query(filter: #Predicate<Routine> { $0.userId == userId }, sort: \Routine.name)
        var desc = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.userId == userId && $0.completedAt != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        desc.fetchLimit = 8
        _recentWorkouts = Query(desc)
    }

    var body: some View {
        List {
            Section {
                Button {
                    startEmpty()
                } label: {
                    Label("空のワークアウトを開始", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.energy)
                }
            }

            Section("ルーティンから開始") {
                if routines.isEmpty {
                    Text("ルーティン未作成").foregroundStyle(.secondary)
                } else {
                    ForEach(routines) { routine in
                        Button { start(from: routine) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(routine.name).foregroundStyle(.primary)
                                    Text("\(routine.routineExercises.count)種目").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill").foregroundStyle(Theme.energy)
                            }
                        }
                    }
                }
            }

            Section("最近のワークアウト") {
                if recentWorkouts.isEmpty {
                    Text("記録なし").foregroundStyle(.secondary)
                } else {
                    ForEach(recentWorkouts) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                WorkoutRow(workout: workout)
                                Text(workout.date, format: .dateTime.year().month().day())
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("ツール") {
                NavigationLink { RoutinesView(userId: userId) } label: { Label("ルーティン管理", systemImage: "list.bullet.rectangle") }
                NavigationLink { ExerciseLibraryView(userId: userId) } label: { Label("種目ライブラリ", systemImage: "figure.strengthtraining.traditional") }
                Button { showPlateCalc = true } label: { Label("プレート計算機", systemImage: "circle.hexagongrid.fill") }
            }
        }
        .navigationTitle("記録")
        .navigationDestination(item: $activeWorkout) { workout in
            WorkoutLoggerView(workout: workout)
        }
        .sheet(isPresented: $showPlateCalc) {
            PlateCalculatorView(initialTarget: 60)
        }
    }

    // MARK: - Start actions

    private func startEmpty() {
        let workout = Workout(userId: userId, date: .now, name: "ワークアウト")
        context.insert(workout)
        try? context.save()
        activeWorkout = workout
    }

    private func start(from routine: Routine) {
        let workout = Workout(userId: userId, date: .now, name: routine.name, routineId: routine.id)
        context.insert(workout)
        let ordered = routine.routineExercises.sorted { $0.orderIndex < $1.orderIndex }
        for (i, re) in ordered.enumerated() {
            guard let exercise = re.exercise else { continue }
            let we = WorkoutExercise(orderIndex: i, workout: workout, exercise: exercise)
            context.insert(we)
            let prev = WorkoutMetrics.previousSets(for: exercise, userId: userId, excludingWorkoutId: workout.id)
            let setCount = max(re.targetSets, prev.count)
            for s in 0..<setCount {
                let p = s < prev.count ? prev[s] : nil
                context.insert(ExerciseSet(setIndex: s, weight: p?.weight ?? 0, reps: p?.reps ?? 0, type: p?.type ?? .normal, workoutExercise: we))
            }
        }
        try? context.save()
        activeWorkout = workout
    }
}
