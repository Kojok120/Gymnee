import SwiftUI
import SwiftData

/// 記録（リデザイン）。タップ式ロガー。
/// 種目カード（重量3/種目名/reps3）を「重量を固定→repsタップで1セット」で記録する。
/// 詳細仕様は docs/record-redesign-spec.md。
struct RecordView: View {
    @Environment(AuthService.self) private var auth
    /// タブから入った時は「記録を開始する」ゲートを挟む。チェックイン経由は飛ばす。
    @State private var gateOpen = false

    var body: some View {
        NavigationStack {
            if let uid = auth.currentUserId {
                if gateOpen {
                    RecordContent(userId: uid, onEnd: { gateOpen = false })
                } else {
                    StartGateView(onStart: { gateOpen = true })
                }
            } else {
                EmptyStateView(systemImage: "person.crop.circle.badge.exclamationmark", title: "未ログイン")
            }
        }
        // チェックイン直後はゲートを飛ばして記録画面へ直行。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeDidCheckIn)) { _ in gateOpen = true }
    }
}

/// 「記録を開始する」ゲート（記録タブから入った時に一度挟む）。
private struct StartGateView: View {
    let onStart: () -> Void
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "dumbbell.fill").font(.system(size: 52)).foregroundStyle(Theme.lime)
            Text("ワークアウトを記録").font(.title2.bold()).foregroundStyle(Theme.textPrimary)
            Text("準備ができたら開始しましょう").font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button(action: onStart) {
                Text("記録を開始する").font(.headline).foregroundStyle(Theme.onLime)
                    .frame(maxWidth: .infinity).padding(Theme.Spacing.md)
                    .background(Theme.limeFill, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg0)
        .navigationTitle("記録").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - モード

/// ①プルダウンのモード。フリー / 今日の計画 / ルーティン。
enum RecordMode: Hashable {
    case free
    case plan
    case routine(UUID)
}

// MARK: - 本体

struct RecordContent: View {
    let userId: UUID
    /// 既存ワークアウトを開いて続き/編集する場合に指定（計画開始・過去編集）。nil は新規ライブ記録。
    var resuming: Workout?
    /// 完了時にタブのゲートへ戻すコールバック（タブ起点のみ）。nil＝従来の待機リセット。
    var onEnd: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(NotificationService.self) private var notifications
    @Environment(AppErrorCenter.self) private var errors

    @Query private var routines: [Routine]
    @Query private var todayPlanned: [PlannedWorkout]
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var restTimer = RestTimer()
    @State private var mode: RecordMode = .free
    @State private var modeInitialized = false
    @State private var activeWorkout: Workout?
    @State private var activePlanId: UUID?
    /// カードごとの weight ルーラー中央値（＝アーム値。記録に使う）。
    @State private var armed: [UUID: Double] = [:]
    /// reps / 秒 ルーラーの中央値（種目ごと・セッション中保持。再描画でスクロール位置を保つ）。
    @State private var repCenters: [UUID: Int] = [:]
    @State private var durCenters: [UUID: Int] = [:]
    @State private var prToast: String?
    @State private var showSummary = false
    @State private var showModePicker = false
    @State private var showExercisePicker = false
    @State private var editingExercise: Exercise?
    @State private var editingSet: ExerciseSet?
    @State private var keypad: KeypadRequest?
    /// フリーで「＋種目」から表向きに加えた種目（このタブ表示中だけ保持）。
    @State private var freeAdded: Set<UUID> = []
    @State private var jumpTarget: MuscleGroup?
    @State private var showOnboarding = false

    @AppStorage("gymnee.recordOnboardingShown") private var onboardingShown = false
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.public.rawValue
    private var defaultVisibility: Visibility { Visibility(rawValue: defaultVisibilityRaw) ?? .public }

    init(userId: UUID, resuming: Workout? = nil, onEnd: (() -> Void)? = nil) {
        self.userId = userId
        self.resuming = resuming
        self.onEnd = onEnd
        _routines = Query(filter: #Predicate<Routine> { $0.userId == userId }, sort: \Routine.name)
        let dayStart = Calendar.current.startOfDay(for: Date())
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        _todayPlanned = Query(
            filter: #Predicate<PlannedWorkout> { $0.userId == userId && !$0.isDone && $0.date >= dayStart && $0.date < dayEnd },
            sort: \PlannedWorkout.date
        )
    }

    private var todayPlan: PlannedWorkout? { todayPlanned.first }

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            logStrip
            cardsArea
        }
        .background(Theme.bg0)
        .navigationTitle("記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if activeWorkout != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { finish() }.bold()
                }
            }
        }
        .safeAreaInset(edge: .bottom) { timerBar }
        .overlay(alignment: .top) { prToastView }
        .sheet(isPresented: $showModePicker) { modePickerSheet }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerView { ex in freeAdded.insert(ex.id) }
        }
        .sheet(item: $editingExercise) { ex in ExerciseEditView(exercise: ex) }
        .sheet(item: $editingSet) { set in EditSetSheet(set: set) { commitSetEdit(set) } }
        .sheet(item: $keypad) { req in
            SlotKeypadSheet(request: req) { value in handleKeypad(req, value: value) }
        }
        .sheet(isPresented: $showSummary, onDismiss: { endSession() }) {
            if let w = activeWorkout {
                WorkoutSummaryView(
                    workout: w,
                    streak: currentStreak,
                    onShare: { showSummary = false },
                    onAnalytics: {
                        showSummary = false
                        NotificationCenter.default.post(name: .gymneeShowAnalytics, object: nil)
                    },
                    onClose: { showSummary = false }
                )
            }
        }
        .sheet(isPresented: $showOnboarding) {
            RecordOnboardingSheet { onboardingShown = true; showOnboarding = false }
        }
        .onAppear {
            discardAbandonedDrafts()
            if let resuming, activeWorkout == nil {
                activeWorkout = resuming
                modeInitialized = true
            } else {
                initializeModeIfNeeded()
                if !onboardingShown { showOnboarding = true }
            }
        }
    }

    /// 未完了(completedAt=nil)の下書きワークアウトをローカル掃除（クラッシュ/中断の残骸）。
    /// 現在編集中(resuming/active)と、計画(isPlanned=true)の予定は除外。下書きは未同期なのでローカル削除のみ。
    private func discardAbandonedDrafts() {
        let uid = userId
        let drafts = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate {
            $0.userId == uid && $0.completedAt == nil && $0.isPlanned == false
        }))) ?? []
        let keepId = resuming?.id ?? activeWorkout?.id
        var changed = false
        for w in drafts where w.id != keepId {
            context.delete(w)
            changed = true
        }
        if changed { try? context.save() }
    }

    // MARK: - ① モードバー + ③ カテゴリ

    private var modeBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button { showModePicker = true } label: {
                HStack(spacing: 6) {
                    Text(modeLabel).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.bg1, in: Capsule())
            }
            Spacer(minLength: 0)
            if mode == .free, !freeGroupedByMuscle.isEmpty {
                Menu {
                    ForEach(freeGroupedByMuscle.map(\.0), id: \.self) { mg in
                        Button(mg.label) { jumpTarget = mg }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text("部位").font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.bg1, in: Capsule())
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var modeLabel: String {
        switch mode {
        case .free: return "フリー"
        case .plan: return todayPlan.map { "本日の計画: \($0.title)" } ?? "本日の計画"
        case .routine(let id): return routines.first { $0.id == id }?.name ?? "ルーティン"
        }
    }

    // MARK: - ② 記録ログ

    /// このセッションの全セット（タップ順＝createdAt 昇順）。
    private var loggedSets: [ExerciseSet] {
        (activeWorkout?.exercises.flatMap { $0.sets } ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    /// ② 記録ログ。常時表示（空ならプレースホルダ）。List なのでスワイプ削除・行タップ編集が効く。
    private var logStrip: some View {
        List {
            if loggedSets.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle").font(.caption)
                    Text("記録するとここに溜まります").font(.caption)
                }
                .foregroundStyle(Theme.textTertiary)
                .listRowBackground(Theme.bg1)
                .listRowSeparator(.hidden)
            } else {
                ForEach(loggedSets) { set in
                    LogRowView(set: set)
                        .listRowBackground(Theme.bg1)
                        .contentShape(Rectangle())
                        .onTapGesture { editingSet = set }
                        .swipeActions { Button("削除", role: .destructive) { deleteSet(set) } }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: loggedSets.isEmpty ? 52 : 160)
        .background(Theme.bg1)
    }

    // MARK: - ④ カード

    @ViewBuilder
    private var cardsArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    switch mode {
                    case .free:
                        freeCardsBody
                    case .plan, .routine:
                        orderedCardsBody
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .onChange(of: jumpTarget) { _, mg in
                guard let mg else { return }
                withAnimation(.smooth) { proxy.scrollTo(mg, anchor: .top) }
                jumpTarget = nil
            }
        }
    }

    /// フリー：最近/よく使う＋このセッション＋手動追加。部位ごとにまとめ、③でジャンプ。
    @ViewBuilder
    private var freeCardsBody: some View {
        let grouped = freeGroupedByMuscle
        if grouped.isEmpty {
            emptyFreeState
        } else {
            ForEach(grouped, id: \.0) { mg, exercises in
                Text(mg.label)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .id(mg)
                cardGrid(exercises.map { CardSpec(exercise: $0, routineExercise: nil, explicit: nil) })
            }
            addExerciseButton
        }
    }

    @ViewBuilder
    private var orderedCardsBody: some View {
        let specs = orderedCardSpecs
        if specs.isEmpty {
            EmptyStateView(systemImage: "calendar.badge.exclamationmark", title: "種目がありません",
                           message: mode == .plan ? "今日の計画に種目がありません。" : "このルーティンに種目がありません。")
        } else {
            cardGrid(specs)
        }
    }

    private func cardGrid(_ specs: [CardSpec]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.md),
                            GridItem(.flexible(), spacing: Theme.Spacing.md)],
                  spacing: Theme.Spacing.md) {
            ForEach(specs, id: \.exercise.id) { spec in
                ExerciseCardView(
                    exercise: spec.exercise,
                    weightCenter: Binding(get: { weightCenter(for: spec) }, set: { armed[spec.exercise.id] = $0 }),
                    repCenter: Binding(get: { Double(repCenter(for: spec)) }, set: { repCenters[spec.exercise.id] = Int($0) }),
                    durCenter: Binding(get: { Double(durCenter(for: spec)) }, set: { durCenters[spec.exercise.id] = Int($0) }),
                    onLogReps: { reps in logReps(reps, spec: spec) },
                    onLogDuration: { dur in logDuration(dur, spec: spec) },
                    onCustomWeight: { keypad = KeypadRequest(exerciseId: spec.exercise.id, kind: .armValue, decimal: true, title: "重量を入力") },
                    onCustomReps: {
                        let isTime = spec.exercise.measurementType == .time
                        keypad = KeypadRequest(exerciseId: spec.exercise.id, kind: .customReps, decimal: false, title: isTime ? "秒を入力" : "回数を入力")
                    },
                    onEdit: { editingExercise = spec.exercise }
                )
            }
        }
    }

    private var addExerciseButton: some View {
        Button { showExercisePicker = true } label: {
            Label("種目を追加", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .tint(Theme.lime)
    }

    private var emptyFreeState: some View {
        VStack(spacing: Theme.Spacing.md) {
            EmptyStateView(systemImage: "dumbbell", title: "種目を追加して始めよう",
                           message: "「種目を追加」から選ぶと、ここにカードが並びます。")
            addExerciseButton
        }
    }

    // MARK: - ⑤ タイマー

    @ViewBuilder
    private var timerBar: some View {
        if let w = activeWorkout {
            HStack(spacing: Theme.Spacing.md) {
                // レスト（左）
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "timer").font(.caption).foregroundStyle(restTimer.isRunning ? Theme.lime : Theme.textTertiary)
                    Text(restTimer.isRunning ? restTimer.displayText : "--:--")
                        .font(.numS).foregroundStyle(restTimer.isRunning ? Theme.textPrimary : Theme.textTertiary)
                        .contentTransition(.numericText())
                    if restTimer.isRunning {
                        Button { restTimer.addTime(30) } label: { Text("+30").font(.caption2.bold()).foregroundStyle(Theme.lime) }
                        Button { restTimer.stop() } label: { Image(systemName: "forward.end.fill").font(.caption2).foregroundStyle(Theme.textSecondary) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
                .background(Theme.bg2, in: Capsule())

                Spacer(minLength: 0)

                // 経過（右）
                TimelineView(.periodic(from: w.date, by: 1)) { _ in
                    HStack(spacing: 6) {
                        Image(systemName: "stopwatch").font(.caption).foregroundStyle(Theme.textTertiary)
                        Text(elapsedString(since: w.date)).font(.numS).foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg).padding(.vertical, Theme.Spacing.sm)
            .background(.ultraThinMaterial)
            .sensoryFeedback(.success, trigger: restTimer.isRunning)
        }
    }

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
            .padding(.horizontal, Theme.Spacing.lg).padding(.vertical, Theme.Spacing.md)
            .background(Theme.celebration, in: Capsule())
            .foregroundStyle(Theme.onLime)
            .shadow(color: Theme.limeGlow, radius: 16, y: 4)
            .padding(.top, Theme.Spacing.sm)
            .transition(.scale(scale: 0.8).combined(with: .move(edge: .top)).combined(with: .opacity))
            .sensoryFeedback(.success, trigger: prToast)
        }
    }

    // MARK: - モード選択シート

    private var modePickerSheet: some View {
        NavigationStack {
            List {
                Button { select(.free) } label: { modeRow("フリー", system: "infinity", selected: mode == .free) }
                if let plan = todayPlan {
                    Button { select(.plan) } label: { modeRow("本日の計画: \(plan.title)", system: "calendar", selected: mode == .plan) }
                }
                Section("ルーティン") {
                    ForEach(routines) { r in
                        HStack {
                            Button { select(.routine(r.id)) } label: {
                                modeRow(r.name, system: "square.stack.3d.up.fill", selected: mode == .routine(r.id))
                            }
                            Spacer()
                            Button { routineSession = .edit(r.id, container: context.container) } label: { Image(systemName: "pencil") }
                                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Button { createRoutine() } label: { Label("ルーティンを作る", systemImage: "plus") }
                }
            }
            .navigationTitle("表示する種目").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { showModePicker = false } } }
            .sheet(item: $routineSession) { s in
                RoutineEditorView(routine: s.routine, editorContext: s.context, isNew: s.isNew)
            }
        }
        .presentationDetents([.medium, .large])
    }

    @State private var routineSession: RoutineEditSession?

    private func modeRow(_ title: String, system: String, selected: Bool) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: system).foregroundStyle(Theme.lime).frame(width: 26)
            Text(title).foregroundStyle(Theme.textPrimary)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Theme.lime) }
        }
    }

    // MARK: - カード仕様 / スロット

    private func centers(for spec: CardSpec) -> RecordSlots.Centers {
        if let explicit = spec.explicit { return explicit }
        return RecordSlots.centers(for: spec.exercise, userId: userId, excludingWorkoutId: activeWorkout?.id)
    }

    /// 各軸の現在中央値（ルーラー位置＝記録に使う値）。weight は armed と兼用。
    private func weightCenter(for spec: CardSpec) -> Double { armed[spec.exercise.id] ?? centers(for: spec).weight }
    private func repCenter(for spec: CardSpec) -> Int { repCenters[spec.exercise.id] ?? centers(for: spec).reps }
    private func durCenter(for spec: CardSpec) -> Int { durCenters[spec.exercise.id] ?? centers(for: spec).duration }

    /// ルーティン/計画モードの順序付きカード。
    private var orderedCardSpecs: [CardSpec] {
        switch mode {
        case .routine(let id):
            guard let r = routines.first(where: { $0.id == id }) else { return [] }
            return r.routineExercises.sorted { $0.orderIndex < $1.orderIndex }.compactMap { re in
                guard let ex = re.exercise else { return nil }
                return CardSpec(exercise: ex, routineExercise: re, explicit: nil)
            }
        case .plan:
            return planCardSpecs
        case .free:
            return []
        }
    }

    /// 計画モード：routineId があればそのルーティン、無ければ detailJSON の PlanExercise。
    private var planCardSpecs: [CardSpec] {
        guard let plan = todayPlan else { return [] }
        if let rid = plan.routineId, let r = routines.first(where: { $0.id == rid }) {
            return r.routineExercises.sorted { $0.orderIndex < $1.orderIndex }.compactMap { re in
                guard let ex = re.exercise else { return nil }
                return CardSpec(exercise: ex, routineExercise: re, explicit: nil)
            }
        }
        guard let json = plan.detailJSON, let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([SupabaseClient.PlanExercise].self, from: data)
        else { return [] }
        return items.compactMap { item in
            guard let ex = allExercises.first(where: { $0.name == item.name }) else { return nil }
            let c = RecordSlots.Centers(weight: max(0, item.weight), reps: max(1, item.reps), duration: 0)
            return CardSpec(exercise: ex, routineExercise: nil, explicit: c)
        }
    }

    /// フリーのカード：部位ごとにまとめた配列。
    private var freeGroupedByMuscle: [(MuscleGroup, [Exercise])] {
        let sessionEx = activeWorkout?.exercises.compactMap { $0.exercise } ?? []
        let recent = allExercises.filter { ex in
            ex.workoutExercises.contains { $0.workout?.userId == userId && !$0.sets.isEmpty }
        }
        let added = allExercises.filter { freeAdded.contains($0.id) }
        var seen = Set<UUID>()
        var result: [Exercise] = []
        for ex in sessionEx + recent + added where seen.insert(ex.id).inserted {
            result.append(ex)
        }
        return MuscleGroup.allCases.compactMap { mg in
            let items = result.filter { $0.muscleGroup == mg }
            return items.isEmpty ? nil : (mg, items)
        }
    }

    // MARK: - 記録アクション

    /// セッション（Workout）を必要なら生成。最初のタップで開始。
    @discardableResult
    private func ensureWorkout() -> Workout {
        if let w = activeWorkout { return w }
        let name: String
        var routineId: UUID?
        switch mode {
        case .free: name = "ワークアウト"
        case .plan:
            name = todayPlan?.title ?? "ワークアウト"
            routineId = todayPlan?.routineId
            activePlanId = todayPlan?.id
        case .routine(let id):
            let r = routines.first { $0.id == id }
            name = r?.name ?? "ワークアウト"
            routineId = id
        }
        let w = Workout(userId: userId, date: .now, name: name, routineId: routineId)
        context.insert(w)
        try? context.save()   // 下書き(completedAt=nil)。サーバー同期は完了時のみ。
        activeWorkout = w
        return w
    }

    /// セッション内でこの種目の WorkoutExercise を取得（無ければ作成）。種目あたり1つ。
    private func workoutExercise(for exercise: Exercise, in workout: Workout) -> WorkoutExercise {
        if let we = workout.exercises.first(where: { $0.exercise?.id == exercise.id }) { return we }
        let we = WorkoutExercise(orderIndex: workout.exercises.count, workout: workout, exercise: exercise)
        context.insert(we)   // 同期は完了時にまとめて。
        return we
    }

    /// weight/bodyweight：weightルーラーの中央値 × reps を1セット記録。
    private func logReps(_ reps: Int, spec: CardSpec) {
        let w = weightCenter(for: spec)
        armed[spec.exercise.id] = w   // ルーラー位置を確定（記録後のジャンプ防止）
        commitSet(exercise: spec.exercise, weight: w, reps: reps, duration: nil)
    }

    /// time：秒を1セット記録。
    private func logDuration(_ seconds: Int, spec: CardSpec) {
        commitSet(exercise: spec.exercise, weight: 0, reps: 0, duration: seconds)
    }

    private func commitSet(exercise: Exercise, weight: Double, reps: Int, duration: Int?) {
        let workout = ensureWorkout()
        let we = workoutExercise(for: exercise, in: workout)
        let set = ExerciseSet(setIndex: we.sets.count, weight: weight, reps: reps,
                              isCompleted: true, durationSeconds: duration, workoutExercise: we)
        context.insert(set)
        try? context.save()   // 下書きはローカルのみ。同期は完了時。

        // PR は表示のみ（確定は完了時。中断したワークアウトでは PR を残さない）。
        if exercise.measurementType != .time, weight > 0, reps > 0 {
            let bests = WorkoutMetrics.bests(for: exercise, userId: userId, excludingSetId: set.id)
            let detected = PRDetector.detect(weight: weight, reps: reps, against: bests)
            if !detected.isEmpty {
                let labels = detected.map(\.type.label).joined(separator: "・")
                showPRToast("PR更新！ \(labels)")
                notifications.notifyPR("\(exercise.name) \(labels)")
            }
        }
        restTimer.exerciseName = exercise.name
        restTimer.start()
    }

    private func deleteSet(_ set: ExerciseSet) {
        context.delete(set)
        try? context.save()   // 下書き中の削除。未同期なのでローカルのみ。
    }

    private func commitSetEdit(_ set: ExerciseSet) {
        set.updatedAt = .now
        set.isDirty = true
        try? context.save()   // 下書き中の編集。同期は完了時。
    }

    private func handleKeypad(_ req: KeypadRequest, value: Double) {
        switch req.kind {
        case .armValue:
            armed[req.exerciseId] = value
        case .customReps:
            guard let spec = currentSpec(for: req.exerciseId) else { return }
            if spec.exercise.measurementType == .time {
                logDuration(Int(value), spec: spec)
            } else {
                logReps(Int(value), spec: spec)
            }
        }
    }

    private func currentSpec(for exerciseId: UUID) -> CardSpec? {
        if let ex = allExercises.first(where: { $0.id == exerciseId }) {
            switch mode {
            case .routine(let id):
                let re = routines.first { $0.id == id }?.routineExercises.first { $0.exercise?.id == exerciseId }
                return CardSpec(exercise: ex, routineExercise: re, explicit: nil)
            default:
                return CardSpec(exercise: ex, routineExercise: nil, explicit: nil)
            }
        }
        return nil
    }

    private func showPRToast(_ message: String) {
        withAnimation { prToast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { prToast = nil }
        }
    }

    // MARK: - 完了 / セッション終了

    private func finish() {
        guard let w = activeWorkout else { return }
        w.completedAt = .now
        w.isPlanned = false
        w.updatedAt = .now
        w.isDirty = true
        // 完了時に PR を確定（中断したワークアウトでは PR を残さない）。
        for we in w.exercises {
            guard let ex = we.exercise, ex.measurementType != .time else { continue }
            for set in we.sets where set.weight > 0 && set.reps > 0 {
                WorkoutMetrics.evaluatePR(set: set, exercise: ex, workout: w, userId: userId, context: context, sync: sync)
            }
        }
        do {
            try context.save()
        } catch {
            errors.report("ワークアウトを保存できませんでした。\(error.localizedDescription)")
            return
        }
        // 完了時に初めてサーバー同期（下書き中は一切送らない）。種目→種目並び→セットの順に送出。
        sync.enqueue(PendingChange(entity: "workouts", recordId: w.id, operation: .upsert, updatedAt: w.updatedAt))
        for we in w.exercises {
            if let ex = we.exercise {
                sync.enqueue(PendingChange(entity: "exercises", recordId: ex.id, operation: .upsert, updatedAt: ex.updatedAt))
            }
            sync.enqueue(PendingChange(entity: "workout_exercises", recordId: we.id, operation: .upsert, updatedAt: we.updatedAt))
            for set in we.sets {
                sync.enqueue(PendingChange(entity: "exercise_sets", recordId: set.id, operation: .upsert, updatedAt: set.updatedAt))
            }
        }
        // 計画の消化リンク。
        if let pid = activePlanId, let plan = todayPlanned.first(where: { $0.id == pid }) {
            plan.isDone = true
            plan.completedWorkoutId = w.id
            plan.updatedAt = .now
            try? context.save()
        }
        restTimer.stop()
        FeedPublisher.publishOwnPosts(
            userId: userId, authorName: auth.session?.displayName, context: context,
            visibilityStore: PostVisibilityStore(), defaultVisibility: defaultVisibility, sync: sync
        )
        showSummary = true
    }

    /// サマリーを閉じた後：待機状態へ戻す。
    private func endSession() {
        if resuming != nil { dismiss(); return }
        if let onEnd { onEnd(); return }   // タブのゲートへ戻す（state は再生成でリセット）
        activeWorkout = nil
        activePlanId = nil
        armed = [:]
        repCenters = [:]
        durCenters = [:]
        freeAdded = []
        modeInitialized = false
        initializeModeIfNeeded()
    }

    private func initializeModeIfNeeded() {
        guard !modeInitialized else { return }
        mode = todayPlan != nil ? .plan : .free
        modeInitialized = true
    }

    private func select(_ newMode: RecordMode) {
        mode = newMode
        showModePicker = false
    }

    private func createRoutine() {
        routineSession = .new(userId: userId, container: context.container)
    }

    // MARK: - 派生

    private func elapsedString(since start: Date) -> String {
        let secs = max(0, Int(Date.now.timeIntervalSince(start)))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    private var currentStreak: Int {
        let uid = userId
        let visits = (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.userId == uid }))) ?? []
        let completed = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.userId == uid && $0.completedAt != nil }))) ?? []
        let days = visits.map(\.visitedAt) + completed.map { $0.completedAt ?? $0.date }
        return StreakCalculator.currentStreak(visitDays: days, calendar: .current)
    }
}

// MARK: - カード仕様

private struct CardSpec {
    let exercise: Exercise
    let routineExercise: RoutineExercise?
    /// 計画モードなどで明示的に与える中央値（nil なら RecordSlots で算出）。
    let explicit: RecordSlots.Centers?
}

// MARK: - 種目カード

private struct ExerciseCardView: View {
    let exercise: Exercise
    @Binding var weightCenter: Double
    @Binding var repCenter: Double
    @Binding var durCenter: Double
    let onLogReps: (Int) -> Void
    let onLogDuration: (Int) -> Void
    let onCustomWeight: () -> Void
    let onCustomReps: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if exercise.measurementType == .time {
                durationRuler
            } else {
                weightRuler
            }
            VStack(spacing: 1) {
                Text(exercise.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if exercise.measurementType == .weight {
                    Text(exercise.weightMode.label).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                } else if exercise.measurementType == .bodyweight {
                    Text("自重＋加重").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                }
            }
            if exercise.measurementType != .time { repsRuler }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.sm)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .contextMenu { Button { onEdit() } label: { Label("種目を編集", systemImage: "pencil") } }
    }

    private var weightRuler: some View {
        SlotRuler(selection: $weightCenter,
                  step: RecordSlots.weightStep(exercise),
                  lowerBound: exercise.measurementType == .bodyweight ? 0 : RecordSlots.weightStep(exercise),
                  decimals: true, unit: "", isAction: false,
                  onCommit: nil, onLongPress: onCustomWeight)
    }
    private var repsRuler: some View {
        SlotRuler(selection: $repCenter,
                  step: 1, lowerBound: 1, decimals: false, unit: "", isAction: true,
                  onCommit: { onLogReps(Int($0)) }, onLongPress: onCustomReps)
    }
    private var durationRuler: some View {
        SlotRuler(selection: $durCenter,
                  step: 5, lowerBound: 5, decimals: false, unit: "秒", isAction: true,
                  onCommit: { onLogDuration(Int($0)) }, onLongPress: onCustomReps)
    }
}

/// 横スクロール等間隔ルーラー。中央にスナップし中央値を `selection` に反映。
/// weight(isAction=false): 中央=アーム(limeFill)。reps/秒(isAction=true): セルタップで onCommit（記録）。
/// セルタップ＝その値へ寄せて選択、長押し＝キーパッド。値列は onAppear で一度だけ生成し再描画でリセットしない。
private struct SlotRuler: View {
    @Binding var selection: Double
    let step: Double
    let lowerBound: Double
    let decimals: Bool
    let unit: String
    let isAction: Bool
    let onCommit: ((Double) -> Void)?
    let onLongPress: () -> Void

    @State private var values: [Double] = []
    @State private var scrolledID: Double?

    var body: some View {
        GeometryReader { geo in
            let cellW = max(1, geo.size.width / 3)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(values, id: \.self) { v in
                        cell(v, cellW: cellW)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, cellW, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledID, anchor: .center)
        }
        .frame(height: 38)
        .onAppear {
            if values.isEmpty {
                values = RecordSlots.rulerValues(center: selection, step: step, lowerBound: lowerBound)
            }
            scrolledID = nearest(selection)
        }
        .onChange(of: scrolledID) { _, new in
            if let new, new != selection { selection = new }
        }
        .onChange(of: selection) { _, sel in
            // 外部ジャンプ(キーパッド)で範囲外なら作り直し。スクロール由来(sel∈values)では作り直さない＝位置維持。
            if !values.contains(sel) {
                values = RecordSlots.rulerValues(center: sel, step: step, lowerBound: lowerBound)
            }
            if scrolledID != sel { scrolledID = nearest(sel) }
        }
        .sensoryFeedback(.selection, trigger: scrolledID)
    }

    private func cell(_ v: Double, cellW: CGFloat) -> some View {
        let isCenter = (scrolledID ?? selection) == v
        return Text(label(v))
            .font(.subheadline.weight(.bold))
            .frame(width: cellW, height: 36)
            .background(isAction ? (isCenter ? Theme.limeSoft : Theme.bg2) : (isCenter ? Theme.limeFill : Theme.bg2),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay {
                if isAction && isCenter {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm).strokeBorder(Theme.lime.opacity(0.6), lineWidth: 1)
                }
            }
            .foregroundStyle(isAction ? (isCenter ? Theme.lime : Theme.textSecondary) : (isCenter ? Theme.onLime : Theme.textSecondary))
            .opacity(isCenter ? 1 : 0.5)
            .id(v)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { scrolledID = v }; selection = v; onCommit?(v) }
            .onLongPressGesture(minimumDuration: 0.4) { onLongPress() }
    }

    private func nearest(_ c: Double) -> Double { values.min(by: { abs($0 - c) < abs($1 - c) }) ?? c }
    private func label(_ v: Double) -> String {
        let s = decimals ? (v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)) : String(Int(v))
        return unit.isEmpty ? s : "\(s)\(unit)"
    }
}

// MARK: - ② ログ行

private struct LogRowView: View {
    let set: ExerciseSet

    var body: some View {
        HStack {
            Text(set.workoutExercise?.exercise?.name ?? "種目")
                .font(.subheadline).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Spacer()
            Text(detail).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Text(set.createdAt, format: .dateTime.hour().minute())
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
    }

    private var detail: String {
        if let d = set.durationSeconds, set.workoutExercise?.exercise?.measurementType == .time {
            return "\(d)秒"
        }
        let w = set.weight == set.weight.rounded() ? String(Int(set.weight)) : String(format: "%.1f", set.weight)
        return "\(w)kg × \(set.reps)"
    }
}

// MARK: - キーパッド

struct KeypadRequest: Identifiable {
    enum Kind { case armValue, customReps }
    let id = UUID()
    let exerciseId: UUID
    let kind: Kind
    let decimal: Bool
    let title: String
}

private struct SlotKeypadSheet: View {
    let request: KeypadRequest
    let onSubmit: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("値", text: $text)
                    .keyboardType(request.decimal ? .decimalPad : .numberPad)
                    .font(.numL)
                    .focused($focused)
            }
            .navigationTitle(request.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("決定") {
                        if let v = Double(text.replacingOccurrences(of: ",", with: ".")) { onSubmit(v) }
                        dismiss()
                    }.bold().disabled(Double(text.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(180)])
    }
}

// MARK: - セット編集

private struct EditSetSheet: View {
    @Bindable var set: ExerciseSet
    let onCommit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var durationText = ""

    private var isTime: Bool { (set.workoutExercise?.exercise?.measurementType) == .time }

    var body: some View {
        NavigationStack {
            Form {
                if isTime {
                    LabeledContent("秒") { TextField("秒", text: $durationText).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                } else {
                    LabeledContent("重量(kg)") { TextField("重量", text: $weightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    LabeledContent("回数") { TextField("回数", text: $repsText).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                }
            }
            .navigationTitle("セットを編集").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        if isTime {
                            set.durationSeconds = Int(durationText) ?? set.durationSeconds
                        } else {
                            set.weight = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? set.weight
                            set.reps = Int(repsText) ?? set.reps
                        }
                        onCommit()
                        dismiss()
                    }.bold()
                }
            }
            .onAppear {
                weightText = set.weight == set.weight.rounded() ? String(Int(set.weight)) : String(format: "%.1f", set.weight)
                repsText = String(set.reps)
                durationText = String(set.durationSeconds ?? 0)
            }
        }
        .presentationDetents([.height(220)])
    }
}

// MARK: - 初回オンボード

private struct RecordOnboardingSheet: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: 0)
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 44)).foregroundStyle(Theme.lime)
            Text("タップで記録")
                .font(.title2.bold()).foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                onboardRow("1", "重量をタップして固定し、回数をタップすると1セット記録されます。")
                onboardRow("2", "重量を変えたい時は別の重量をタップ。範囲外の値は長押しで入力できます。")
                onboardRow("3", "候補の数値は使うほどあなたに最適化されます。最初は手入力で大丈夫。")
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            Spacer(minLength: 0)
            Button(action: onDone) {
                Text("はじめる").font(.headline).foregroundStyle(Theme.onLime)
                    .frame(maxWidth: .infinity).padding(Theme.Spacing.md)
                    .background(Theme.limeFill, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            }
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.bg0)
        .interactiveDismissDisabled()
    }

    private func onboardRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(num)
                .font(.caption.bold()).foregroundStyle(Theme.onLime)
                .frame(width: 22, height: 22).background(Theme.lime, in: Circle())
            Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
    }
}
