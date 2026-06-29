import SwiftUI
import SwiftData

/// 録画中の暫定PRスパーク 1 件（その場表示用・非永続）。
struct PRSpark: Identifiable, Equatable {
    let id = UUID()
    let exerciseName: String
    let typesLabel: String
}

/// 記録（リデザイン）。タップ式ロガー。
/// 種目カード（重量3/種目名/reps3）を「重量を固定→repsタップで1セット」で記録する。
/// 詳細仕様は docs/record-redesign-spec.md。
struct RecordView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var context
    /// タブから入った時は「記録を開始する」ゲートを挟む。チェックイン経由は飛ばす。
    @State private var gateOpen = false
    /// 計画/予定の「開始」から渡された、記録タブで再開するワークアウト（nil＝新規ライブ記録）。
    @State private var resumeTarget: Workout?
    /// 未完了の下書き（クラッシュ/中断の自動保存）。ゲートに「再開」導線を出すために観測する。
    @Query(filter: #Predicate<Workout> { $0.completedAt == nil && $0.isPlanned == false }, sort: \Workout.date, order: .reverse)
    private var openDrafts: [Workout]

    /// 中身（セット or メモ）のある自動保存下書き。あれば再開を促す。
    private func resumableDraft(for uid: UUID) -> Workout? {
        openDrafts.first { w in
            w.userId == uid && (w.exercises.contains { !$0.sets.isEmpty } || !(w.note ?? "").isEmpty)
        }
    }

    var body: some View {
        NavigationStack {
            if let uid = auth.currentUserId {
                if gateOpen {
                    RecordContent(userId: uid, resuming: resumeTarget, onEnd: { gateOpen = false; resumeTarget = nil })
                } else {
                    StartGateView(
                        userId: uid,
                        resumable: resumableDraft(for: uid),
                        onStart: { resumeTarget = nil; gateOpen = true },
                        onResume: { draft in resumeTarget = draft; gateOpen = true },
                        onDiscard: { draft in context.delete(draft); try? context.save() }
                    )
                }
            } else {
                EmptyStateView(systemImage: "person.crop.circle.badge.exclamationmark", title: "未ログイン")
            }
        }
        // チェックイン直後はゲートを飛ばして記録画面へ直行（新規記録）。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeDidCheckIn)) { _ in resumeTarget = nil; gateOpen = true }
        // 計画/予定の「開始」→ 記録タブで当該ワークアウトを再開（カレンダータブから遷移してくる）。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeStartWorkout)) { note in
            guard let idStr = note.userInfo?["workoutId"] as? String, let id = UUID(uuidString: idStr) else { return }
            let found = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id }))) ?? []
            if let w = found.first {
                resumeTarget = w
                gateOpen = true
            }
        }
    }
}

/// 「記録を開始する」ゲート（記録タブから入った時に一度挟む）。
private struct StartGateView: View {
    let userId: UUID
    /// 自動保存された中断中の下書き（あれば再開導線を出す）。
    var resumable: Workout? = nil
    let onStart: () -> Void
    var onResume: (Workout) -> Void = { _ in }
    var onDiscard: (Workout) -> Void = { _ in }

    private enum Route: Hashable { case history }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            if let draft = resumable { resumeCard(draft) }
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
            // これまでの記録を一覧で振り返る導線（記録一覧＝日付/種目ごと）。
            NavigationLink(value: Route.history) {
                Label("これまでの記録を見る", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg0)
        .navigationTitle("記録").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Route.self) { _ in
            HistoryView(userId: userId)
        }
    }

    /// 中断中の記録を再開/破棄するカード（自動保存の可視化）。
    private func resumeCard(_ draft: Workout) -> some View {
        let setCount = draft.exercises.reduce(0) { $0 + $1.sets.count }
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("途中の記録があります", systemImage: "arrow.uturn.backward.circle.fill")
                .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
            Text("\(draft.name)・\(setCount)セットを自動保存しました。")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Spacing.sm) {
                Button { onResume(draft) } label: {
                    Text("再開").font(.subheadline.bold()).foregroundStyle(Theme.onLime)
                        .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.limeFill, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                }
                Button(role: .destructive) { onDiscard(draft) } label: {
                    Text("破棄").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.lime.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, Theme.Spacing.lg)
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
    /// 有酸素の距離km ルーラー中央値（種目ごと・セッション中保持）。
    @State private var distCenters: [UUID: Double] = [:]
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
    @State private var showCancelConfirm = false
    @State private var showMemo = false
    /// 録画中の暫定PRスパーク（その場の「更新ペース！」表示・非永続。確定は完了時）。
    @State private var prSpark: PRSpark?

    @AppStorage("gymnee.recordOnboardingShown") private var onboardingShown = false
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.friends.rawValue
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
        .overlay(alignment: .top) { prSparkBanner }
        .navigationTitle("記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("キャンセル") { attemptCancel() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { openMemo() } label: {
                    Image(systemName: hasMemo ? "note.text" : "square.and.pencil")
                        .foregroundStyle(hasMemo ? Theme.lime : Theme.textSecondary)
                }
                .accessibilityLabel("メモ")
            }
            if activeWorkout != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { finish() }.bold()
                }
            }
        }
        .alert("この記録を破棄しますか？", isPresented: $showCancelConfirm) {
            Button("破棄してカレンダーへ", role: .destructive) { cancelRecording() }
            Button("続ける", role: .cancel) {}
        } message: {
            Text("記録した内容は保存されません。")
        }
        .safeAreaInset(edge: .bottom) { timerBar }
        .sheet(isPresented: $showModePicker) { modePickerSheet }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerView { ex in freeAdded.insert(ex.id) }
        }
        .sheet(item: $editingExercise) { ex in ExerciseEditView(exercise: ex) }
        .sheet(item: $editingSet) { set in EditSetSheet(set: set) { commitSetEdit(set) } }
        .sheet(isPresented: $showMemo) {
            if let w = activeWorkout { WorkoutMemoSheet(workout: w) { try? context.save() } }
        }
        .sheet(item: $keypad) { req in
            SlotKeypadSheet(request: req) { value in handleKeypad(req, value: value) }
        }
        .sheet(isPresented: $showSummary, onDismiss: { endSession() }) {
            if let w = activeWorkout {
                WorkoutSummaryView(
                    workout: w,
                    streak: currentStreak,
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

    /// 中身の無い空の下書き(completedAt=nil)だけをローカル掃除する。
    /// セットやメモのある下書きは「自動保存された記録」として残し、クラッシュ/中断後に復帰できるようにする。
    /// 現在編集中(resuming/active)と計画(isPlanned=true)は除外。下書きは未同期なのでローカル削除のみ。
    private func discardAbandonedDrafts() {
        let uid = userId
        let drafts = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate {
            $0.userId == uid && $0.completedAt == nil && $0.isPlanned == false
        }))) ?? []
        let keepId = resuming?.id ?? activeWorkout?.id
        var changed = false
        for w in drafts where w.id != keepId {
            let hasSets = w.exercises.contains { !$0.sets.isEmpty }
            let hasNote = !(w.note ?? "").isEmpty
            guard !hasSets, !hasNote else { continue }   // 中身のある下書きは残す（自動保存）。
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
        case .routine(let id): return routines.first { $0.id == id }?.name ?? "カスタムセット"
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
                           message: mode == .plan ? "今日の計画に種目がありません。" : "このカスタムセットに種目がありません。")
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
                    distanceCenter: Binding(get: { distanceCenter(for: spec) }, set: { distCenters[spec.exercise.id] = $0 }),
                    onLogReps: { reps in logReps(reps, spec: spec) },
                    onLogDuration: { dur in logDuration(dur, spec: spec) },
                    onLogCardio: { dist, mins in logCardio(distanceKm: dist, minutes: mins, spec: spec) },
                    onCustomWeight: { keypad = KeypadRequest(exerciseId: spec.exercise.id, kind: .armValue, decimal: true, title: "重量を入力") },
                    onCustomReps: {
                        let title: String
                        switch spec.exercise.measurementType {
                        case .time: title = "秒を入力"
                        case .cardio: title = "分を入力"
                        default: title = "回数を入力"
                        }
                        keypad = KeypadRequest(exerciseId: spec.exercise.id, kind: .customReps, decimal: false, title: title)
                    },
                    onCustomDistance: { keypad = KeypadRequest(exerciseId: spec.exercise.id, kind: .distanceValue, decimal: true, title: "距離(km)を入力") },
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

    // MARK: - モード選択シート

    private var modePickerSheet: some View {
        NavigationStack {
            List {
                Button { select(.free) } label: { modeRow("フリー", system: "infinity", selected: mode == .free) }
                if let plan = todayPlan {
                    Button { select(.plan) } label: { modeRow("本日の計画: \(plan.title)", system: "calendar", selected: mode == .plan) }
                }
                Section("カスタムセット") {
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
                    Button { createRoutine() } label: { Label("カスタムセットを作る", systemImage: "plus") }
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
    private func distanceCenter(for spec: CardSpec) -> Double { distCenters[spec.exercise.id] ?? centers(for: spec).distanceKm }

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

    /// フリーのカード：部位ごとにまとめた配列。仕様書「最近中心＋全種目」。
    /// セッション中はカード順を固定する：先頭に置く「最近」は完了済み履歴のある種目のみで判定し、
    /// 記録途中の下書きでは並べ替えない（記録してもカードが動かない／完了後の次回に順序が更新される）。
    private var freeGroupedByMuscle: [(MuscleGroup, [Exercise])] {
        let recent = allExercises.filter { ex in
            ex.workoutExercises.contains { $0.workout?.userId == userId && $0.workout?.completedAt != nil && !$0.sets.isEmpty }
        }
        var seen = Set<UUID>()
        var ordered: [Exercise] = []
        // ①最近中心（完了済み履歴のある種目）を先頭に。
        for ex in recent where seen.insert(ex.id).inserted {
            ordered.append(ex)
        }
        // ②残りの全種目を名前順（allExercises は @Query で name ソート済み）で追加。
        for ex in allExercises where seen.insert(ex.id).inserted {
            ordered.append(ex)
        }
        return MuscleGroup.allCases.compactMap { mg in
            let items = ordered.filter { $0.muscleGroup == mg }
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
        // 自重のみは重量軸が無いので weight=0 を記録（過去セットの値を引きずらない）。
        let bodyweightOnly = spec.exercise.measurementType == .bodyweight && spec.exercise.loadMode == .none
        commitSet(exercise: spec.exercise, weight: bodyweightOnly ? 0 : w, reps: reps, duration: nil)
    }

    /// time：秒を1セット記録。
    private func logDuration(_ seconds: Int, spec: CardSpec) {
        commitSet(exercise: spec.exercise, weight: 0, reps: 0, duration: seconds)
    }

    /// cardio：距離km ＋ 時間（分）を1セット記録（時間は秒に換算して保存）。
    private func logCardio(distanceKm: Double, minutes: Int, spec: CardSpec) {
        distCenters[spec.exercise.id] = distanceKm   // ルーラー位置を確定（記録後のジャンプ防止）
        durCenters[spec.exercise.id] = minutes
        commitSet(exercise: spec.exercise, weight: 0, reps: 0, duration: minutes * 60, distanceKm: distanceKm)
    }

    private func commitSet(exercise: Exercise, weight: Double, reps: Int, duration: Int?, distanceKm: Double? = nil) {
        let workout = ensureWorkout()
        let we = workoutExercise(for: exercise, in: workout)
        let set = ExerciseSet(setIndex: we.sets.count, weight: weight, reps: reps,
                              isCompleted: true, durationSeconds: duration, distanceKm: distanceKm, workoutExercise: we)
        context.insert(set)
        try? context.save()   // 下書きはローカルのみ。同期は完了時。
        // PR の確定・永続は完了時にまとめて。ここでは履歴ベストとの純粋比較で「更新ペース！」を
        // その場表示するだけ（非永続。中断したワークアウトに PR を残さない設計を壊さない）。
        showProvisionalPRIfNeeded(set: set, exercise: exercise)
        restTimer.exerciseName = exercise.name
        restTimer.start()
    }

    /// 録画中の暫定PRスパーク表示（上端からスライドイン）。
    @ViewBuilder private var prSparkBanner: some View {
        if let spark = prSpark {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "trophy.fill").foregroundStyle(Theme.onLime)
                VStack(alignment: .leading, spacing: 0) {
                    Text("自己ベスト更新ペース！").font(.subheadline.bold()).foregroundStyle(Theme.onLime)
                    Text("\(spark.exerciseName) · \(spark.typesLabel)")
                        .font(.caption).foregroundStyle(Theme.onLime.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg).padding(.vertical, Theme.Spacing.md)
            .background(Theme.limeFill, in: Capsule())
            .shadow(color: Theme.limeGlow, radius: 16, y: 4)
            .padding(.top, Theme.Spacing.sm)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
            .sensoryFeedback(.success, trigger: spark.id)
        }
    }

    /// 履歴ベスト（この set を除く）を上回ったら暫定スパークを出す。永続化はしない。
    private func showProvisionalPRIfNeeded(set: ExerciseSet, exercise: Exercise) {
        let bests = WorkoutMetrics.bests(for: exercise, userId: userId, excludingSetId: set.id)
        let detected = PRDetector.detect(
            measurementType: exercise.measurementType,
            weight: set.weight, reps: set.reps, durationSeconds: set.durationSeconds,
            against: bests, loadMode: exercise.loadMode
        )
        guard !detected.isEmpty else { return }
        let label = detected.map(\.type.label).joined(separator: "・")
        let spark = PRSpark(exerciseName: exercise.name, typesLabel: label)
        withAnimation(.bouncy) { prSpark = spark }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { if prSpark?.id == spark.id { prSpark = nil } }
            }
        }
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

    /// このワークアウトにメモが付いているか（ツールバーアイコンの状態表示用）。
    private var hasMemo: Bool { !(activeWorkout?.note ?? "").isEmpty }

    /// メモを開く。未開始ならセッションを作ってからメモ編集（メモのある下書きは破棄されない）。
    private func openMemo() {
        ensureWorkout()
        showMemo = true
    }

    private func handleKeypad(_ req: KeypadRequest, value: Double) {
        switch req.kind {
        case .armValue:
            armed[req.exerciseId] = value
        case .distanceValue:
            distCenters[req.exerciseId] = value
        case .customReps:
            guard let spec = currentSpec(for: req.exerciseId) else { return }
            switch spec.exercise.measurementType {
            case .time:   logDuration(Int(value), spec: spec)
            case .cardio: logCardio(distanceKm: distanceCenter(for: spec), minutes: Int(value), spec: spec)
            default:      logReps(Int(value), spec: spec)
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
            // 自重(自重のみ/補助は weight=0/補助量)も PR 対象。ウェイト種目だけ weight>0 を要求。
            let isBW = ex.measurementType == .bodyweight
            for set in we.sets where set.reps > 0 && (isBW || set.weight > 0) {
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
    /// 左上「キャンセル」。記録済みセットがあれば確認、無ければ即キャンセル。
    private func attemptCancel() {
        let hasSets = !(activeWorkout?.exercises.flatMap { $0.sets } ?? []).isEmpty
        if hasSets { showCancelConfirm = true } else { cancelRecording() }
    }

    /// 記録を破棄してカレンダーへ。未完了の下書きはローカル削除（未同期）。
    /// 計画から開始していた場合は、その計画を未消化に戻して計画リストへ復帰させる。
    private func cancelRecording() {
        if let w = activeWorkout, w.completedAt == nil {
            let wid = w.id
            let descriptor = FetchDescriptor<PlannedWorkout>(predicate: #Predicate { $0.completedWorkoutId == wid })
            for plan in (try? context.fetch(descriptor)) ?? [] {
                plan.isDone = false
                plan.completedWorkoutId = nil
                plan.updatedAt = .now
            }
            context.delete(w)
            try? context.save()
        }
        activeWorkout = nil
        activePlanId = nil
        armed = [:]
        repCenters = [:]
        durCenters = [:]
        distCenters = [:]
        freeAdded = []
        // カレンダータブへ切替え、タブのゲート/pushed view を閉じる。
        NotificationCenter.default.post(name: .gymneeShowCalendar, object: nil)
        // タブ起点（チェックイン/計画開始）はゲートへ戻す。カレンダーからの過去編集 push は閉じる。
        if let onEnd { onEnd() } else { dismiss() }
    }

    private func endSession() {
        if let onEnd { onEnd(); return }   // タブ起点：ゲートへ戻す（state は再生成でリセット）
        if resuming != nil { dismiss(); return }   // カレンダーからの過去編集 push を閉じる
        activeWorkout = nil
        activePlanId = nil
        armed = [:]
        repCenters = [:]
        durCenters = [:]
        distCenters = [:]
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
    @Binding var distanceCenter: Double
    let onLogReps: (Int) -> Void
    let onLogDuration: (Int) -> Void
    let onLogCardio: (Double, Int) -> Void
    let onCustomWeight: () -> Void
    let onCustomReps: () -> Void
    let onCustomDistance: () -> Void
    let onEdit: () -> Void

    /// 自重のみ（重量軸を出さない）。
    private var bodyweightOnly: Bool {
        exercise.measurementType == .bodyweight && exercise.loadMode == .none
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            topRuler
            VStack(spacing: 1) {
                Text(exercise.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if exercise.measurementType == .weight {
                    Text(exercise.weightMode.label).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                } else if exercise.measurementType == .bodyweight {
                    Text(exercise.loadMode.loadAxisLabel).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                } else if exercise.measurementType == .cardio {
                    Text("距離 · 時間").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                }
            }
            bottomRuler
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.sm)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .contextMenu { Button { onEdit() } label: { Label("種目を編集", systemImage: "pencil") } }
    }

    /// 上段ルーラー：ウェイト=重量 / 時間=秒 / 有酸素=距離。自重のみは無し。
    @ViewBuilder private var topRuler: some View {
        switch exercise.measurementType {
        case .time:   durationRuler
        case .cardio: distanceRuler
        case .weight, .bodyweight:
            if !bodyweightOnly { weightRuler }   // 自重のみ(loadMode == none)は重量軸なし。
        }
    }

    /// 下段ルーラー（記録アクション）：ウェイト/自重=回数 / 有酸素=時間(分) / 時間=無し（上段が記録）。
    @ViewBuilder private var bottomRuler: some View {
        switch exercise.measurementType {
        case .time:   EmptyView()
        case .cardio: cardioMinuteRuler
        case .weight, .bodyweight: repsRuler
        }
    }

    private var weightRuler: some View {
        // 0kg も選べる（下限0）。アシスト/ウォームアップ等で0を記録したいケースに対応。
        SlotRuler(selection: $weightCenter,
                  step: RecordSlots.weightStep(exercise),
                  lowerBound: 0,
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
    /// 有酸素の距離（km）。中央＝アーム（記録時の距離）。
    private var distanceRuler: some View {
        SlotRuler(selection: $distanceCenter,
                  step: 0.5, lowerBound: 0, decimals: true, unit: "km", isAction: false,
                  onCommit: nil, onLongPress: onCustomDistance)
    }
    /// 有酸素の時間（分）。タップで「距離＋その時間」を1セット記録。
    private var cardioMinuteRuler: some View {
        SlotRuler(selection: $durCenter,
                  step: 5, lowerBound: 5, decimals: false, unit: "分", isAction: true,
                  onCommit: { onLogCardio(distanceCenter, Int($0)) }, onLongPress: onCustomReps)
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
        HStack(spacing: Theme.Spacing.sm) {
            Text(set.workoutExercise?.exercise?.name ?? "種目")
                .font(.subheadline).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Spacer(minLength: Theme.Spacing.sm)
            Text(detail).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Text(set.createdAt, format: .dateTime.hour().minute())
                .font(.caption2).foregroundStyle(Theme.textTertiary)
            // 行タップで編集できることを示すアフォーダンス（タップ＝編集 / 左スワイプ＝削除）。
            Image(systemName: "square.and.pencil")
                .font(.caption).foregroundStyle(Theme.textTertiary)
        }
    }

    private var detail: String { self.set.detailText }
}

// MARK: - キーパッド

struct KeypadRequest: Identifiable {
    enum Kind { case armValue, customReps, distanceValue }
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
    @State private var distanceText = ""
    @State private var minutesText = ""

    private var measurement: MeasurementType { self.set.workoutExercise?.exercise?.measurementType ?? .weight }
    private var isTime: Bool { measurement == .time }
    private var isCardio: Bool { measurement == .cardio }

    var body: some View {
        NavigationStack {
            Form {
                if isCardio {
                    LabeledContent("距離(km)") { TextField("距離", text: $distanceText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    LabeledContent("時間(分)") { TextField("分", text: $minutesText).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                } else if isTime {
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
                        if isCardio {
                            set.distanceKm = Double(distanceText.replacingOccurrences(of: ",", with: ".")) ?? set.distanceKm
                            if let m = Int(minutesText) { set.durationSeconds = m * 60 }
                        } else if isTime {
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
                let km = set.distanceKm ?? 0
                distanceText = km == km.rounded() ? String(Int(km)) : String(format: "%.1f", km)
                minutesText = String((set.durationSeconds ?? 0) / 60)
            }
        }
        .presentationDetents([.height(220)])
    }
}

// MARK: - メモ

/// ワークアウトのメモ（任意）。記録中いつでも編集でき、完了時にサーバーへ同期される。
private struct WorkoutMemoSheet: View {
    @Bindable var workout: Workout
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("このワークアウトのメモ") {
                    TextField("調子・気づき・コンディションなど（任意）", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .navigationTitle("メモ").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        workout.note = trimmed.isEmpty ? nil : trimmed
                        workout.updatedAt = .now
                        workout.isDirty = true
                        onSave()
                        dismiss()
                    }.bold()
                }
            }
            .onAppear { text = workout.note ?? "" }
        }
        .presentationDetents([.medium])
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
