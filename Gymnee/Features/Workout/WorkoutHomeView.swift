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
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                startHero
                toolsRow
                routinesSection
                recentSection
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.bg0)
        .navigationTitle("記録")
        .navigationDestination(item: $activeWorkout) { workout in
            WorkoutLoggerView(workout: workout)
        }
        .navigationDestination(for: NavTarget.self) { target in
            switch target {
            case .routines: RoutinesView(userId: userId)
            case .library: ExerciseLibraryView(userId: userId)
            }
        }
        .sheet(isPresented: $showPlateCalc) {
            PlateCalculatorView(initialTarget: 60)
        }
    }

    private enum NavTarget: Hashable { case routines, library }

    // MARK: - Sections

    private var startHero: some View {
        Button { startEmpty() } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "plus")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.onLime)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.25), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("空のワークアウトを開始")
                        .font(.headline)
                    Text("今この瞬間から記録する")
                        .font(.caption)
                        .foregroundStyle(Theme.onLime.opacity(0.7))
                }
                Spacer()
            }
            .foregroundStyle(Theme.onLime)
            .padding(Theme.Spacing.lg)
            .background(Theme.celebration, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: Theme.limeGlow, radius: 16, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var toolsRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            NavigationLink(value: NavTarget.routines) { toolCard(icon: "list.bullet.rectangle.fill", label: "ルーティン") }
            NavigationLink(value: NavTarget.library) { toolCard(icon: "figure.strengthtraining.traditional", label: "種目") }
            Button { showPlateCalc = true } label: { toolCard(icon: "circle.hexagongrid.fill", label: "プレート") }
        }
        .buttonStyle(.plain)
    }

    private func toolCard(icon: String, label: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.lime)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "ルーティンから開始")
            if routines.isEmpty {
                Text("ルーティン未作成。テンプレから作れます。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gymneeCard()
            } else {
                ForEach(routines) { routine in
                    Button { start(from: routine) } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundStyle(Theme.lime)
                                .frame(width: 40, height: 40)
                                .background(Theme.limeSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(routine.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                Text("\(routine.routineExercises.count)種目").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Theme.lime)
                        }
                        .gymneeCard(padding: Theme.Spacing.md)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "最近のワークアウト")
            if recentWorkouts.isEmpty {
                Text("記録なし。最初のワークアウトを始めましょう。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gymneeCard()
            } else {
                ForEach(recentWorkouts) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            WorkoutRow(workout: workout)
                            Text(workout.date, format: .dateTime.year().month().day())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gymneeCard(padding: Theme.Spacing.md)
                    }
                    .buttonStyle(.plain)
                }
            }
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
            let we = WorkoutExercise(orderIndex: i, restSeconds: re.restSeconds, workout: workout, exercise: exercise)
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
