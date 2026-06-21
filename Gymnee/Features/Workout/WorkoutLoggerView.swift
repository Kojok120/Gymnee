import SwiftUI
import SwiftData

/// L3 ワークアウトロガー（§6.5・最重要）。前回値オートフィル・セット入力・PR自動検出・レストタイマー。
struct WorkoutLoggerView: View {
    @Bindable var workout: Workout

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(NotificationService.self) private var notifications
    @Environment(AppErrorCenter.self) private var errors

    @State private var restTimer = RestTimer()
    @State private var showExercisePicker = false
    @State private var plateTarget: Double?
    @State private var prToast: String?
    @State private var editingNote: WorkoutExercise?

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
        .sheet(item: $editingNote) { we in
            NavigationStack {
                Form {
                    TextField("種目メモ（例: フォーム意識・痛みなど）", text: noteBinding(we), axis: .vertical)
                        .lineLimit(3...6)
                }
                .navigationTitle(we.exercise?.name ?? "メモ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完了") { try? context.save(); editingNote = nil }
                    }
                }
            }
            .presentationDetents([.height(220)])
        }
    }

    private struct PlateTarget: Identifiable { let weight: Double; var id: Double { weight } }

    private func noteBinding(_ we: WorkoutExercise) -> Binding<String> {
        Binding(get: { we.note ?? "" }, set: { we.note = $0.isEmpty ? nil : $0; we.updatedAt = .now })
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            TextField("ワークアウト名", text: $workout.name)
                .font(.title3.bold())
            if let gym = workout.visit?.gym {
                Label(gym.name, systemImage: "building.2.fill").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xl) {
                inlineMetric(label: "種目", value: "\(orderedExercises.count)")
                inlineMetric(label: "セット", value: "\(completedSets)/\(totalSets)")
                inlineMetric(label: "ボリューム", value: String(format: "%.0f", totalVolume), unit: "kg")
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private func inlineMetric(label: String, value: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            OverlineLabel(text: label)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.numS).foregroundStyle(Theme.textPrimary)
                if let unit { Text(unit).font(.caption2).foregroundStyle(Theme.textTertiary) }
            }
        }
    }

    private func exerciseSection(_ we: WorkoutExercise) -> some View {
        Section {
            if let note = we.note, !note.isEmpty {
                Label(note, systemImage: "note.text").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(we.sets.sorted { $0.setIndex < $1.setIndex }) { set in
                SetRowView(set: set) { onSetCompleted(set, in: we) }
                    .swipeActions {
                        Button("削除", role: .destructive) { deleteSet(set, from: we) }
                    }
            }
            Button {
                addSet(to: we)
            } label: {
                Label("セットを追加", systemImage: "plus.circle").font(.subheadline)
            }
            if let history = historyText(for: we) {
                Label(history, systemImage: "clock.arrow.circlepath")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let suggest = suggestionText(for: we) {
                Label(suggest, systemImage: "target")
                    .font(.caption2).foregroundStyle(Theme.energy)
            }
        } header: {
            HStack(spacing: 6) {
                if we.supersetGroup != nil {
                    Image(systemName: "link").font(.caption2).foregroundStyle(supersetColor(we))
                }
                Text(we.exercise?.name ?? "種目")
                if let hint = previousHint(for: we) {
                    Text(hint).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                exerciseMenu(we)
            }
        } footer: {
            if let est = estimated1RM(for: we), est > 0 {
                Text(String(format: "推定1RM %.1fkg", est))
            }
        }
        .listRowBackground(we.supersetGroup != nil ? supersetColor(we).opacity(0.06) : Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func exerciseMenu(_ we: WorkoutExercise) -> some View {
        Menu {
            Button { addWarmup(to: we) } label: { Label("ウォームアップを追加", systemImage: "flame") }
            Button { plateTarget = topWeight(of: we) } label: { Label("プレート計算", systemImage: "circle.hexagongrid.fill") }
            Button { editingNote = we } label: { Label("メモを編集", systemImage: "note.text") }
            if we.supersetGroup != nil {
                Button { clearSuperset(we) } label: { Label("スーパーセット解除", systemImage: "link") }
            } else if canSupersetWithNext(we) {
                Button { linkSupersetWithNext(we) } label: { Label("次とスーパーセット", systemImage: "link") }
            }
            Button(role: .destructive) { deleteExercise(we) } label: { Label("種目を削除", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle").font(.body)
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

    /// 浮遊するグラス製レストタイマーピル（§6.5）。残時間を表すドレインリング + カウントダウン。
    @ViewBuilder
    private var restBar: some View {
        if restTimer.isRunning {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle().stroke(Theme.bg3, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: max(0.001, 1 - restTimer.progress))
                        .stroke(Theme.lime, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Theme.limeGlow, radius: 4)
                    Image(systemName: "timer").font(.caption2).foregroundStyle(Theme.lime)
                }
                .frame(width: 38, height: 38)
                .animation(.timerTick, value: restTimer.progress)

                VStack(alignment: .leading, spacing: 0) {
                    Text("レスト").font(.overline).foregroundStyle(Theme.textTertiary)
                    Text(restTimer.displayText)
                        .font(.numM)
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 0)

                Button { restTimer.addTime(30) } label: {
                    Text("+30s")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.lime)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.limeSoft, in: Capsule())
                }
                Button { restTimer.stop() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(Theme.Spacing.sm)
                        .background(Theme.bg2, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.lime.opacity(0.25), lineWidth: 1) }
            .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .sensoryFeedback(.success, trigger: restTimer.isRunning)
        }
    }

    /// PR 達成バナー（アプリで最も特別な瞬間）。
    @ViewBuilder
    private var prToastView: some View {
        if let prToast {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "medal.fill").font(.headline)
                VStack(alignment: .leading, spacing: 0) {
                    Text("NEW PR").font(.overline).tracking(1.5)
                    Text(prToast).font(.subheadline.bold())
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.celebration, in: Capsule())
            .foregroundStyle(Theme.onLime)
            .shadow(color: Theme.limeGlow, radius: 16, y: 4)
            .padding(.top, Theme.Spacing.sm)
            .transition(.scale(scale: 0.8).combined(with: .move(edge: .top)).combined(with: .opacity))
            .sensoryFeedback(.success, trigger: prToast)
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
        restTimer.start(seconds: we.restSeconds)
        if !detected.isEmpty {
            let labels = detected.map(\.type.label).joined(separator: "・")
            showPRToast("PR更新！ \(labels)")
            notifications.notifyPR("\(exercise.name) \(labels)")
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
        do {
            try context.save()
        } catch {
            errors.report("ワークアウトを保存できませんでした。\(error.localizedDescription)")
            return
        }
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

    private var totalSets: Int {
        orderedExercises.flatMap(\.sets).filter { $0.type != .warmup }.count
    }

    private var completedSets: Int {
        orderedExercises.flatMap(\.sets).filter { $0.type != .warmup && $0.isCompleted }.count
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

    /// 直近セッションのインライン履歴（例: 6/14 80×6 · 6/11 75×8）。
    private func historyText(for we: WorkoutExercise) -> String? {
        guard let exercise = we.exercise else { return nil }
        let recent = WorkoutMetrics.recentTopSets(for: exercise, userId: userId, excludingWorkoutId: workout.id, limit: 3)
        guard !recent.isEmpty else { return nil }
        let f = DateFormatter(); f.dateFormat = "M/d"
        return recent.map { String(format: "%@ %.0f×%d", f.string(from: $0.date), $0.weight, $0.reps) }
            .joined(separator: " · ")
    }

    /// 履歴ベスト推定1RM からの %1RM 目標重量（例: 目標 5→102.5 / 8→90 / 12→80kg）。
    private func suggestionText(for we: WorkoutExercise) -> String? {
        guard let exercise = we.exercise else { return nil }
        let e1RM = WorkoutMetrics.bestE1RM(for: exercise, userId: userId, excludingWorkoutId: workout.id)
        guard e1RM > 0 else { return nil }
        let s = StrengthSuggester.suggestions(e1RM: e1RM)
        let body = s.map { String(format: "%d→%g", $0.reps, $0.weight) }.joined(separator: " / ")
        return "目標 \(body)kg"
    }

    // MARK: - Warmup / Superset actions

    private func addWarmup(to we: WorkoutExercise) {
        let existing = we.sets.sorted { $0.setIndex < $1.setIndex }
        let working = existing.filter { $0.type != .warmup }
        // 本番重量：作業セットの最大、無ければ履歴の8レップ推奨。
        let target: Double = {
            if let maxW = working.map(\.weight).max(), maxW > 0 { return maxW }
            guard let ex = we.exercise else { return 0 }
            let e1RM = WorkoutMetrics.bestE1RM(for: ex, userId: userId, excludingWorkoutId: workout.id)
            return StrengthSuggester.workingWeight(e1RM: e1RM, reps: 8)
        }()
        let warmups = WarmupCalculator.sets(workingWeight: target)
        guard !warmups.isEmpty else { return }

        // 既存ウォームアップを除去してから先頭に差し込み、全セットを再採番。
        for s in existing where s.type == .warmup { context.delete(s) }
        var idx = 0
        for w in warmups {
            context.insert(ExerciseSet(setIndex: idx, weight: w.weight, reps: w.reps, type: .warmup, isCompleted: false, workoutExercise: we))
            idx += 1
        }
        for s in working { s.setIndex = idx; idx += 1 }
        try? context.save()
    }

    private func canSupersetWithNext(_ we: WorkoutExercise) -> Bool {
        orderedExercises.contains { $0.orderIndex == we.orderIndex + 1 }
    }

    private func linkSupersetWithNext(_ we: WorkoutExercise) {
        guard let next = orderedExercises.first(where: { $0.orderIndex == we.orderIndex + 1 }) else { return }
        let group = we.orderIndex
        we.supersetGroup = group
        next.supersetGroup = group
        we.updatedAt = .now; next.updatedAt = .now
        try? context.save()
    }

    private func clearSuperset(_ we: WorkoutExercise) {
        let group = we.supersetGroup
        for ex in orderedExercises where ex.supersetGroup == group {
            ex.supersetGroup = nil
            ex.updatedAt = .now
        }
        try? context.save()
    }

    private func deleteExercise(_ we: WorkoutExercise) {
        context.delete(we)
        try? context.save()
    }

    private func supersetColor(_ we: WorkoutExercise) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .teal, .indigo]
        guard let g = we.supersetGroup else { return Theme.energy }
        return palette[abs(g) % palette.count]
    }
}
