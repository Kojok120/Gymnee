import SwiftUI
import SwiftData

/// L3 ワークアウトロガー（§6.5・最重要）。前回値オートフィル・セット入力・PR自動検出・レストタイマー。
struct WorkoutLoggerView: View {
    @Bindable var workout: Workout

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync

    @State private var restTimer = RestTimer()
    @State private var showExercisePicker = false
    @State private var plateTarget: Double?
    @State private var prToast: String?

    private var userId: UUID { auth.currentUserId ?? UUID() }
    private var orderedExercises: [WorkoutExercise] {
        workout.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        List {
            headerSection
            ForEach(orderedExercises) { we in
                exerciseSection(we)
            }
            addExerciseButton
        }
        .listStyle(.insetGrouped)
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完了") { finish() }.bold()
            }
        }
        .safeAreaInset(edge: .bottom) { restBar }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerView { addExercise($0) }
        }
        .sheet(item: Binding(get: { plateTarget.map { PlateTarget(weight: $0) } }, set: { plateTarget = $0?.weight })) { target in
            PlateCalculatorView(initialTarget: target.weight)
        }
        .overlay(alignment: .top) { prToastView }
    }

    private struct PlateTarget: Identifiable { let weight: Double; var id: Double { weight } }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            TextField("ワークアウト名", text: $workout.name)
                .font(.headline)
            if let gym = workout.visit?.gym {
                Label(gym.name, systemImage: "building.2.fill").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Label("\(orderedExercises.count)種目", systemImage: "list.bullet")
                Spacer()
                Label(String(format: "総ボリューム %.0fkg", totalVolume), systemImage: "scalemass")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func exerciseSection(_ we: WorkoutExercise) -> some View {
        Section {
            ForEach(we.sets.sorted { $0.setIndex < $1.setIndex }) { set in
                SetRowView(set: set) { onSetCompleted(set, in: we) }
                    .swipeActions {
                        Button("削除", role: .destructive) { deleteSet(set, from: we) }
                    }
            }
            Button {
                addSet(to: we)
            } label: {
                Label("セットを追加", systemImage: "plus.circle")
                    .font(.subheadline)
            }
        } header: {
            HStack {
                Text(we.exercise?.name ?? "種目")
                Spacer()
                if let hint = previousHint(for: we) {
                    Text(hint).font(.caption2).foregroundStyle(.secondary)
                }
                Button {
                    plateTarget = topWeight(of: we)
                } label: {
                    Image(systemName: "circle.hexagongrid.fill").font(.caption)
                }
            }
        } footer: {
            if let est = estimated1RM(for: we), est > 0 {
                Text(String(format: "推定1RM %.1fkg", est))
            }
        }
    }

    private var addExerciseButton: some View {
        Section {
            Button {
                showExercisePicker = true
            } label: {
                Label("種目を追加", systemImage: "plus")
            }
        }
    }

    // MARK: - Rest timer bar

    @ViewBuilder
    private var restBar: some View {
        if restTimer.isRunning {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "timer").foregroundStyle(Theme.energy)
                Text(restTimer.displayText).font(.title3.monospacedDigit().bold())
                ProgressView(value: restTimer.progress).tint(Theme.energy)
                Button("+30") { restTimer.addTime(30) }.font(.caption.bold())
                Button {
                    restTimer.stop()
                } label: { Image(systemName: "stop.fill") }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var prToastView: some View {
        if let prToast {
            Label(prToast, systemImage: "trophy.fill")
                .font(.subheadline.bold())
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(.yellow.opacity(0.95), in: Capsule())
                .foregroundStyle(.black)
                .shadow(radius: 6)
                .padding(.top, Theme.Spacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func addExercise(_ exercise: Exercise) {
        let we = WorkoutExercise(orderIndex: workout.exercises.count, workout: workout, exercise: exercise)
        context.insert(we)
        let prev = WorkoutMetrics.previousSets(for: exercise, userId: userId, excludingWorkoutId: workout.id)
        if prev.isEmpty {
            context.insert(ExerciseSet(setIndex: 0, workoutExercise: we))
        } else {
            for (i, p) in prev.enumerated() {
                context.insert(ExerciseSet(setIndex: i, weight: p.weight, reps: p.reps, type: p.type, workoutExercise: we))
            }
        }
        try? context.save()
        sync.enqueue(PendingChange(entity: "workout_exercises", recordId: we.id, operation: .upsert, updatedAt: we.updatedAt))
    }

    private func addSet(to we: WorkoutExercise) {
        let last = we.sets.max { $0.setIndex < $1.setIndex }
        let set = ExerciseSet(
            setIndex: we.sets.count,
            weight: last?.weight ?? 0,
            reps: last?.reps ?? 0,
            type: .normal,
            workoutExercise: we
        )
        context.insert(set)
        try? context.save()
    }

    private func deleteSet(_ set: ExerciseSet, from we: WorkoutExercise) {
        context.delete(set)
        try? context.save()
    }

    private func onSetCompleted(_ set: ExerciseSet, in we: WorkoutExercise) {
        guard let exercise = we.exercise else { return }
        let detected = WorkoutMetrics.evaluatePR(set: set, exercise: exercise, workout: workout, userId: userId, context: context, sync: sync)
        sync.enqueue(PendingChange(entity: "exercise_sets", recordId: set.id, operation: .upsert, updatedAt: set.updatedAt))
        try? context.save()
        restTimer.exerciseName = exercise.name
        restTimer.start()
        if !detected.isEmpty {
            let labels = detected.map(\.type.label).joined(separator: "・")
            showPRToast("PR更新！ \(labels)")
        }
    }

    private func showPRToast(_ message: String) {
        withAnimation { prToast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { prToast = nil }
        }
    }

    private func finish() {
        workout.completedAt = .now
        workout.isPlanned = false
        workout.updatedAt = .now
        workout.isDirty = true
        try? context.save()
        sync.enqueue(PendingChange(entity: "workouts", recordId: workout.id, operation: .upsert, updatedAt: workout.updatedAt))
        restTimer.stop()
        dismiss()
    }

    // MARK: - Derived

    private var totalVolume: Double {
        orderedExercises
            .flatMap(\.sets)
            .filter { $0.type != .warmup }
            .reduce(0) { $0 + $1.volume }
    }

    private func topWeight(of we: WorkoutExercise) -> Double {
        we.sets.map(\.weight).max() ?? 60
    }

    private func estimated1RM(for we: WorkoutExercise) -> Double? {
        let best = we.sets
            .filter { $0.type != .warmup && $0.weight > 0 && $0.reps > 0 }
            .map { OneRepMax.estimate(weight: $0.weight, reps: $0.reps) }
            .max()
        return best
    }

    private func previousHint(for we: WorkoutExercise) -> String? {
        guard let exercise = we.exercise else { return nil }
        let prev = WorkoutMetrics.previousSets(for: exercise, userId: userId, excludingWorkoutId: workout.id)
        guard let top = prev.first else { return nil }
        return String(format: "前回 %.0f×%d", top.weight, top.reps)
    }
}
