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
    @Environment(LocalSyncEngine.self) private var sync
    /// タブから入った時は「記録を開始する」ゲートを挟む。チェックイン経由は飛ばす。
    @State private var gateOpen = false
    /// 計画/予定の「開始」から渡された、記録タブで再開するワークアウト（nil＝新規ライブ記録）。
    @State private var resumeTarget: Workout?
    /// ゲートの「テンプレから始める」で作ったルーティンを初期モードにする（nil＝既定の計画/フリー）。
    @State private var startMode: RecordMode?
    @State private var showTemplatePicker = false
    /// 未完了の下書き（クラッシュ/中断の自動保存）。ゲートに「再開」導線を出すために観測する。
    @Query(filter: #Predicate<Workout> { $0.completedAt == nil && $0.isPlanned == false }, sort: \Workout.date, order: .reverse)
    private var openDrafts: [Workout]
    /// 完了ワークアウト（テンプレ導線の表示判定）。body 内の fetchCount を避け @Query で反応的に観測する。
    @Query(filter: #Predicate<Workout> { $0.completedAt != nil })
    private var completedWorkouts: [Workout]

    /// 中身（セット or メモ）のある自動保存下書きをすべて返す（新しい順）。各々をゲートにカード表示する。
    private func resumableDrafts(for uid: UUID) -> [Workout] {
        openDrafts.filter { w in
            w.userId == uid && (w.exercises.contains { !$0.sets.isEmpty } || !(w.note ?? "").isEmpty)
        }
    }

    /// テンプレからルーティンを作成・保存し、それを初期モードにして記録を開始する
    /// （初回アクティベーション導線。保存＋同期は RoutineEditorView の完了時と同じ形）。
    private func startWithTemplate(_ template: RoutineTemplates.Template, userId: UUID) {
        let routine = RoutineTemplates.create(template, userId: userId, context: context)
        routine.isDirty = true
        try? context.save()
        var pending = [PendingChange(entity: "routines", recordId: routine.id, operation: .upsert, updatedAt: routine.updatedAt)]
        for re in routine.routineExercises {
            if let ex = re.exercise {
                pending.append(PendingChange(entity: "exercises", recordId: ex.id, operation: .upsert, updatedAt: ex.updatedAt))
            }
            pending.append(PendingChange(entity: "routine_exercises", recordId: re.id, operation: .upsert, updatedAt: re.updatedAt))
        }
        sync.enqueueBatch(pending)
        resumeTarget = nil
        startMode = .routine(routine.id)
        gateOpen = true
    }

    /// 下書きを破棄する。計画から開始していた下書きは、リンクした PlannedWorkout を未消化へ戻してから削除する
    /// （cancelRecording と同じ。これをしないと未完了なのに計画が消費済みのまま planner から消える）。
    private func discardDraft(_ draft: Workout) {
        let did = draft.id
        let descriptor = FetchDescriptor<PlannedWorkout>(predicate: #Predicate { $0.completedWorkoutId == did })
        for plan in (try? context.fetch(descriptor)) ?? [] {
            plan.isDone = false
            plan.completedWorkoutId = nil
            plan.updatedAt = .now
        }
        context.delete(draft)
        try? context.save()
    }

    var body: some View {
        NavigationStack {
            if let uid = auth.currentUserId {
                if gateOpen {
                    RecordContent(userId: uid, resuming: resumeTarget, initialMode: startMode,
                                  onEnd: { gateOpen = false; resumeTarget = nil; startMode = nil })
                } else {
                    StartGateView(
                        userId: uid,
                        resumables: resumableDrafts(for: uid),
                        onStart: { resumeTarget = nil; startMode = nil; gateOpen = true },
                        onResume: { draft in resumeTarget = draft; startMode = nil; gateOpen = true },
                        onDiscard: { draft in discardDraft(draft) },
                        onTemplates: { showTemplatePicker = true },
                        showTemplates: !completedWorkouts.contains { $0.userId == uid }
                    )
                    .sheet(isPresented: $showTemplatePicker) {
                        RoutineTemplatePicker(
                            onSelect: { t in
                                showTemplatePicker = false
                                startWithTemplate(t, userId: uid)
                            },
                            onCancel: { showTemplatePicker = false }
                        )
                    }
                }
            } else {
                EmptyStateView(systemImage: "person.crop.circle.badge.exclamationmark", title: "未ログイン")
            }
        }
        // チェックイン直後はゲートを飛ばして記録画面へ直行（新規記録）。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeDidCheckIn)) { _ in resumeTarget = nil; gateOpen = true }
        // 計画/予定の「開始」→ 記録タブで当該ワークアウトを再開（カレンダータブから遷移してくる）。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeStartWorkout)) { note in
            guard let idStr = note.userInfo?["workoutId"] as? String, let id = UUID(uuidString: idStr),
                  let uid = auth.currentUserId else { return }
            // 通知の id は古い/不正な値で他ユーザーの下書きを指し得るため、現在ユーザー所有に限定する。
            let found = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id && $0.userId == uid }))) ?? []
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
    /// 自動保存された中断中の下書き（あれば1件ずつカードで再開/破棄導線を出す）。
    var resumables: [Workout] = []
    let onStart: () -> Void
    var onResume: (Workout) -> Void = { _ in }
    var onDiscard: (Workout) -> Void = { _ in }
    /// テンプレ選択シートを開く（テンプレのルーティンで即開始）。
    var onTemplates: () -> Void = {}
    /// テンプレ導線の表示（新規ユーザー＝完了記録なしのみ true）。
    var showTemplates: Bool = true


    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    if !resumables.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("途中の記録").font(.subheadline.bold()).foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(resumables) { draft in resumeCard(draft) }
                        }
                    }
                    // 記録の開始導線（ヘッダー＋ボタン）を画面中央にまとめる。
                    VStack(spacing: Theme.Spacing.lg) {
                        VStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "dumbbell.fill").font(.system(size: 52)).foregroundStyle(Theme.lime)
                            Text("ワークアウトを記録").font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                            Text("準備ができたら開始しましょう").font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }
                        VStack(spacing: Theme.Spacing.md) {
                            Button(action: onStart) {
                                Text("記録を開始する").font(.headline).foregroundStyle(Theme.onLime)
                                    .frame(maxWidth: .infinity).padding(Theme.Spacing.md)
                                    .background(Theme.limeFill, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                            }
                            // 補助導線は1行に収める（CTA 下の縦積みは圧迫感が出るため）。
                            // テンプレは新規ユーザー（完了記録なし）だけに出す活性化導線。
                            // 履歴リンクは単発クロージャ型：RecordContent が push 経由(カレンダー編集/
                            // ワークアウト詳細)で開かれても pushed view 上の navigationDestination(for:) に
                            // 依存せず確実に遷移する（iOS 26.5 で子リンクが解決されない問題の回避。
                            // List/ForEach 内ではないのでハングもしない）。
                            HStack(spacing: Theme.Spacing.xl) {
                                if showTemplates {
                                    Button(action: onTemplates) {
                                        Label("テンプレから始める", systemImage: "square.grid.2x2")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                NavigationLink {
                                    HistoryView(userId: userId)
                                } label: {
                                    Label(showTemplates ? "記録を見る" : "これまでの記録を見る",
                                          systemImage: "list.bullet.rectangle")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                // 中身が画面より短ければ縦中央、長ければスクロール。
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
            }
            .background(Theme.bg0)
        }
        .navigationTitle("記録").navigationBarTitleDisplayMode(.inline)
    }

    /// 中断中の記録1件を再開/破棄するカード（開始日時＋内容の一部を表示）。
    private func resumeCard(_ draft: Workout) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Label("途中の記録", systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(draft.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            Text(DraftSummary.text(for: draft))
                .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
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
    }
}

/// 下書き（途中の記録）の内容サマリー文字列（種目名の一部＋セット数）。ゲートと記録一覧で共用。
enum DraftSummary {
    @MainActor
    static func text(for draft: Workout) -> String {
        let setCount = draft.exercises.reduce(0) { $0 + $1.sets.count }
        let names = draft.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { $0.exercise?.name }
        let head = names.prefix(2).joined(separator: ", ")
        let more = names.count > 2 ? " 他\(names.count - 2)種目" : ""
        if names.isEmpty {
            return setCount > 0 ? "\(setCount)セット" : "メモのみ"
        }
        return "\(head)\(more) ・ \(setCount)セット"
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
    /// 開始時のモード指定（ゲートの「テンプレから始める」用）。nil＝既定（今日計画あれば計画、無ければフリー）。
    var initialMode: RecordMode?
    /// 完了時にタブのゲートへ戻すコールバック（タブ起点のみ）。nil＝従来の待機リセット。
    var onEnd: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
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
    /// centers（前回セット履歴の走査）の計算結果キャッシュ。カードごと・軸ごとの Binding get が
    /// 毎描画で履歴を再走査しないようにする。描画中（Binding get 内）に書き込むため、
    /// @State の値型辞書ではなく参照型に持つ（identity 不変＝ビュー更新を誘発しない）。
    @State private var centersCache = CentersCache()
    @State private var showSummary = false
    @State private var showModePicker = false
    @State private var showAddExercise = false
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
    /// フリーのカード（部位ごと）。種目数×完了履歴の関連走査が重いので毎描画ではなくキャッシュする。
    @State private var freeGroups: [(MuscleGroup, [Exercise])] = []

    @AppStorage("gymnee.recordOnboardingShown") private var onboardingShown = false
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.friends.rawValue
    private var defaultVisibility: Visibility { Visibility(rawValue: defaultVisibilityRaw) ?? .public }

    init(userId: UUID, resuming: Workout? = nil, initialMode: RecordMode? = nil, onEnd: (() -> Void)? = nil) {
        self.userId = userId
        self.resuming = resuming
        self.initialMode = initialMode
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
            ToolbarItem(placement: .topBarTrailing) {
                // 完了の場所を最初から見せる（メモを開くまで現れない＝在処が分かりづらい問題の解消）。
                // 記録(セット)が1件も無いうちは無効。セットを記録すると有効になる。
                Button("完了") { finish() }.bold()
                    .disabled(!hasRecordedSets)
            }
        }
        .alert("この記録を破棄しますか？", isPresented: $showCancelConfirm) {
            Button("破棄してカレンダーへ", role: .destructive) { cancelRecording() }
            Button("続ける", role: .cancel) {}
        } message: {
            Text("記録した内容は保存されません。")
        }
        .safeAreaInset(edge: .bottom) { timerBar }
        // フォアグラウンド復帰時にレスト残りを実時計から即時同期（バックグラウンド中の凍結表示を解消）。
        .onChange(of: scenePhase) { _, phase in if phase == .active { restTimer.refresh() } }
        // 除外対象（編集中ワークアウト）が変わると前回値の計算結果も変わるためキャッシュを捨てる。
        .onChange(of: activeWorkout?.id) { _, _ in centersCache.values.removeAll() }
        .sheet(isPresented: $showModePicker) { modePickerSheet }
        .sheet(isPresented: $showAddExercise) {
            AddExerciseView(onCreated: { ex in freeAdded.insert(ex.id) })
        }
        // 種目編集（器具・計測タイプ変更）は centers の既定値に影響するため、閉じたらキャッシュを捨てる。
        .sheet(item: $editingExercise, onDismiss: { centersCache.values.removeAll() }) { ex in ExerciseInspectorView(exercise: ex, userId: userId) }
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
        // フリーのカード群は種目数が変わった時だけ作り直す（毎描画の関連走査を避ける）。
        .task(id: allExercises.count) { rebuildFreeGroups() }
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
            if mode == .free, !freeGroups.isEmpty {
                Menu {
                    ForEach(freeGroups.map(\.0), id: \.self) { mg in
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
        let sets = loggedSets   // flatMap+sort を1描画で1回だけに（空判定・行・高さで使い回す）。
        return List {
            if sets.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle").font(.caption)
                    Text("記録するとここに溜まります").font(.caption)
                }
                .foregroundStyle(Theme.textTertiary)
                .listRowBackground(Theme.bg1)
                .listRowSeparator(.hidden)
            } else {
                ForEach(sets) { set in
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
        .frame(height: sets.isEmpty ? 52 : 160)
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
        let grouped = freeGroups
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
                    onCustomWeight: {
                        // バーベルの合計重量入力ではプレート換算（片側内訳）を併記する。
                        // 自重（加重/補助）は符号切替（加重＋/補助−）を出す。
                        let plates = spec.exercise.equipment == .barbell && spec.exercise.measurementType == .weight
                        let signed = spec.exercise.measurementType == .bodyweight && spec.exercise.loadMode != .none
                        keypad = KeypadRequest(exerciseId: spec.exercise.id, kind: .armValue, decimal: true,
                                               title: signed ? "加重/補助を入力" : "重量を入力",
                                               showPlates: plates, signedLoad: signed)
                    },
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
                    onOpen: { editingExercise = spec.exercise }
                )
            }
        }
    }

    private var addExerciseButton: some View {
        Button { showAddExercise = true } label: {
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
        let id = spec.exercise.id
        if let cached = centersCache.values[id] { return cached }
        let computed = RecordSlots.centers(for: spec.exercise, userId: userId, excludingWorkoutId: activeWorkout?.id)
        centersCache.values[id] = computed
        return computed
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
    private func rebuildFreeGroups() {
        let recent = allExercises.filter { ex in
            ex.workoutExercises.contains { $0.workout?.userId == userId && $0.workout?.completedAt != nil && !$0.sets.isEmpty }
        }
        var seenIds = Set<UUID>()
        // 同名別id の重複種目（プリセットが同期で増殖するケース等）を1枚にまとめる。
        // recent（履歴のある方）を先に処理するので、記録済みの種目を優先して残す。
        var seenNames = Set<String>()
        var ordered: [Exercise] = []
        func addIfNew(_ ex: Exercise) {
            let nameKey = ex.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !seenNames.contains(nameKey), seenIds.insert(ex.id).inserted else { return }
            seenNames.insert(nameKey)
            ordered.append(ex)
        }
        // ①最近中心（完了済み履歴のある種目）を先頭に。
        for ex in recent { addIfNew(ex) }
        // ②残りの全種目を名前順（allExercises は @Query で name ソート済み）で追加。
        for ex in allExercises { addIfNew(ex) }
        freeGroups = MuscleGroup.allCases.compactMap { mg in
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
        // 不正値（負・非有限）と minutes*60 のオーバーフローを排除してから保存する。
        let km = (distanceKm.isFinite && distanceKm >= 0) ? distanceKm : 0
        let mins = max(0, min(minutes, 100_000))
        distCenters[spec.exercise.id] = km   // ルーラー位置を確定（記録後のジャンプ防止）
        durCenters[spec.exercise.id] = mins
        commitSet(exercise: spec.exercise, weight: 0, reps: 0, duration: mins * 60, distanceKm: km)
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
        // 最後のセットを消したら、空になった種目エントリ(WorkoutExercise)も削除する。
        // 残すと完了後の投稿/詳細に「セットなし」の種目として出てしまうため。
        let we = set.workoutExercise
        let wasLastSet = (we?.sets.count ?? 0) <= 1
        context.delete(set)
        if wasLastSet, let we { context.delete(we) }
        try? context.save()   // 下書き中の削除。未同期なのでローカルのみ。
    }

    private func commitSetEdit(_ set: ExerciseSet) {
        set.updatedAt = .now
        set.isDirty = true
        try? context.save()   // 下書き中の編集。同期は完了時。
    }

    /// このワークアウトにメモが付いているか（ツールバーアイコンの状態表示用）。
    private var hasMemo: Bool { !(activeWorkout?.note ?? "").isEmpty }
    /// 記録済みセットが1件以上あるか（完了ボタンの有効/無効判定）。
    private var hasRecordedSets: Bool { !(activeWorkout?.exercises.flatMap { $0.sets } ?? []).isEmpty }

    /// メモを開く。未開始ならセッションを作ってからメモ編集（メモのある下書きは破棄されない）。
    private func openMemo() {
        ensureWorkout()
        showMemo = true
    }

    /// Double→Int の安全変換。NaN/∞/範囲外での `Int(_:)` トラップを防ぎ、0以上・上限内へ丸める。
    private func safeCount(_ v: Double, cap: Int = 100_000) -> Int {
        guard v.isFinite else { return 0 }
        return max(0, min(Int(v.rounded()), cap))
    }

    private func handleKeypad(_ req: KeypadRequest, value: Double) {
        switch req.kind {
        case .armValue:
            armed[req.exerciseId] = value.isFinite ? value : 0
        case .distanceValue:
            distCenters[req.exerciseId] = (value.isFinite && value >= 0) ? value : 0
        case .customReps:
            guard let spec = currentSpec(for: req.exerciseId) else { return }
            switch spec.exercise.measurementType {
            case .time:   logDuration(safeCount(value), spec: spec)
            case .cardio: logCardio(distanceKm: distanceCenter(for: spec), minutes: safeCount(value), spec: spec)
            default:      logReps(safeCount(value), spec: spec)
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
        // セット0件の種目エントリは投稿/同期前に取り除く（記録ミスで残った空種目を「セットなし」で残さない）。
        for we in Array(w.exercises) where we.sets.isEmpty { context.delete(we) }
        // 初回完了のみ時刻を確定する（編集での再完了は既存の完了時刻・総合時間を保持）。
        if w.completedAt == nil {
            let now = Date.now
            if let secs = WorkoutDuration.finalizedSeconds(date: w.date, completedAt: now) {
                // ライブ記録：実経過を総合時間として確定。
                w.completedAt = now
                w.durationSeconds = secs
            } else {
                // 経過が実時間でない場合（過去日の後追い記録など）：完了日はワークアウトの
                // 日付側に合わせ、総合時間は未計測(nil)のままサマリーでの手動入力に委ねる。
                w.completedAt = Calendar.current.isDate(w.date, inSameDayAs: now) ? now : w.date
            }
        }
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
        // enqueue は1件ごとに outbox 全書き出しが走るため、まとめて enqueueBatch（ディスク書込1回）にする。
        var pending: [PendingChange] = [PendingChange(entity: "workouts", recordId: w.id, operation: .upsert, updatedAt: w.updatedAt)]
        for we in w.exercises {
            if let ex = we.exercise {
                pending.append(PendingChange(entity: "exercises", recordId: ex.id, operation: .upsert, updatedAt: ex.updatedAt))
            }
            pending.append(PendingChange(entity: "workout_exercises", recordId: we.id, operation: .upsert, updatedAt: we.updatedAt))
            for set in we.sets {
                pending.append(PendingChange(entity: "exercise_sets", recordId: set.id, operation: .upsert, updatedAt: set.updatedAt))
            }
        }
        sync.enqueueBatch(pending)
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
        mode = initialMode ?? (todayPlan != nil ? .plan : .free)
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

/// centers 計算結果の入れ物（種目ID→中央値）。描画中の Binding get から書き込むため
/// 参照型にして @State の値変更（＝描画中の状態更新警告）を避ける。
private final class CentersCache {
    var values: [UUID: RecordSlots.Centers] = [:]
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
    let onOpen: () -> Void

    /// 自重のみ（重量軸を出さない）。
    private var bodyweightOnly: Bool {
        exercise.measurementType == .bodyweight && exercise.loadMode == .none
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            topRuler
            // 名前部（ウェイト/回数のルーラー以外）をタップ → 種目インスペクタへ遷移。
            VStack(spacing: 1) {
                Text(exercise.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if exercise.measurementType == .weight, exercise.weightMode != .none {
                    Text(exercise.weightMode.label).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                } else if exercise.measurementType == .bodyweight {
                    Text(exercise.loadMode.loadAxisLabel).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                } else if exercise.measurementType == .cardio {
                    Text("距離 · 時間").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }
            bottomRuler
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.md)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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
        // 値列は種目特性で決まる（ダンベル1kg→2kg区分、自重は補助−⟷加重＋の一本軸、他は等差・下限0）。
        let ex = exercise
        return SlotRuler(selection: $weightCenter,
                  makeValues: { RecordSlots.weightRulerValues(for: ex, center: $0) },
                  decimals: true, unit: "", isAction: false,
                  signedLoad: ex.measurementType == .bodyweight,
                  onCommit: nil, onLongPress: onCustomWeight)
    }
    private var repsRuler: some View {
        SlotRuler(selection: $repCenter,
                  makeValues: { RecordSlots.rulerValues(center: $0, step: 1, lowerBound: 1) },
                  decimals: false, unit: "", isAction: true,
                  onCommit: { onLogReps(Int($0)) }, onLongPress: onCustomReps)
    }
    private var durationRuler: some View {
        SlotRuler(selection: $durCenter,
                  makeValues: { RecordSlots.rulerValues(center: $0, step: 5, lowerBound: 5) },
                  decimals: false, unit: "秒", isAction: true,
                  onCommit: { onLogDuration(Int($0)) }, onLongPress: onCustomReps)
    }
    /// 有酸素の距離（km）。中央＝アーム（記録時の距離）。
    private var distanceRuler: some View {
        SlotRuler(selection: $distanceCenter,
                  makeValues: { RecordSlots.rulerValues(center: $0, step: 0.5, lowerBound: 0) },
                  decimals: true, unit: "km", isAction: false,
                  onCommit: nil, onLongPress: onCustomDistance)
    }
    /// 有酸素の時間（分）。タップで「距離＋その時間」を1セット記録。
    private var cardioMinuteRuler: some View {
        SlotRuler(selection: $durCenter,
                  makeValues: { RecordSlots.rulerValues(center: $0, step: 5, lowerBound: 5) },
                  decimals: false, unit: "分", isAction: true,
                  onCommit: { onLogCardio(distanceCenter, Int($0)) }, onLongPress: onCustomReps)
    }
}

/// 横スクロール等間隔ルーラー。中央にスナップし中央値を `selection` に反映。
/// weight(isAction=false): 中央=アーム(limeFill)。reps/秒(isAction=true): セルタップで onCommit（記録）。
/// セルタップ＝その値へ寄せて選択、長押し＝キーパッド。値列は onAppear で一度だけ生成し再描画でリセットしない。
private struct SlotRuler: View {
    @Binding var selection: Double
    /// 中心値 → ルーラーの値列。等差だけでなく区分刻み（ダンベル/自重の補助⟷加重）にも対応する。
    let makeValues: (Double) -> [Double]
    let decimals: Bool
    let unit: String
    let isAction: Bool
    /// 負値を「補助」として表示する（自重の一本軸）。
    var signedLoad: Bool = false
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
                values = makeValues(selection)
            }
            scrolledID = nearest(selection)
        }
        .onChange(of: scrolledID) { _, new in
            if let new, new != selection { selection = new }
        }
        .onChange(of: selection) { _, sel in
            // 外部ジャンプ(キーパッド)で範囲外なら作り直し。スクロール由来(sel∈values)では作り直さない＝位置維持。
            if !values.contains(sel) {
                values = makeValues(sel)
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
        // 符号付き（自重の一本軸）: 負=補助、0=自重、正=加重。
        if signedLoad {
            if v == 0 { return "自重" }
            let mag = abs(v)
            let s = mag == mag.rounded() ? String(Int(mag)) : String(format: "%.1f", mag)
            return v < 0 ? "補\(s)" : "+\(s)"
        }
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
    /// バーベル種目の重量入力でプレート換算（片側内訳）を併記する。
    var showPlates: Bool = false
    /// 自重（加重/補助）の符号付き入力（加重＋/補助−の切替を表示）。
    var signedLoad: Bool = false
}

private struct SlotKeypadSheet: View {
    let request: KeypadRequest
    let onSubmit: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool
    /// 符号付き入力（自重の加重＋/補助−）の方向。テンキーに±が無いためセグメントで切替える。
    @State private var loadDirection = 1.0
    /// バーベルのバー重量（プレート換算用・ジムのバーに合わせて選択を記憶）。
    @AppStorage("gymnee.barWeightKg") private var barWeight = 20.0

    var body: some View {
        NavigationStack {
            Form {
                TextField("値", text: $text)
                    .keyboardType(request.decimal ? .decimalPad : .numberPad)
                    .font(.numL)
                    .focused($focused)
                if request.signedLoad {
                    Picker("種別", selection: $loadDirection) {
                        Text("加重 ＋").tag(1.0)
                        Text("補助 −").tag(-1.0)
                    }
                    .pickerStyle(.segmented)
                }
                if request.showPlates {
                    LabeledContent("バー") {
                        Picker("", selection: $barWeight) {
                            Text("20kg").tag(20.0)
                            Text("15kg").tag(15.0)
                            Text("10kg").tag(10.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }
                    Label(plateText, systemImage: "circle.circle")
                        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .navigationTitle(request.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("決定") {
                        if let v = Double(text.replacingOccurrences(of: ",", with: ".")) {
                            // 符号付き入力（自重）は選択方向（加重＋/補助−）を符号に反映。
                            onSubmit(request.signedLoad ? abs(v) * loadDirection : v)
                        }
                        dismiss()
                    }.bold().disabled(Double(text.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(request.showPlates ? 300 : 180)])
    }

    /// 入力中の合計重量に対する片側プレート内訳（バーベル種目のみ表示）。
    private var plateText: String {
        guard let target = Double(text.replacingOccurrences(of: ",", with: ".")) else {
            return "合計重量を入れると片側のプレート内訳が出ます"
        }
        guard let b = PlateCalculator.breakdown(target: target, bar: barWeight) else {
            return "バー\(SetFormatting.weightString(barWeight))kg 未満です"
        }
        if b.perSide.isEmpty {
            return b.remainder > 0 ? "バーのみ（端数 \(SetFormatting.weightString(b.remainder))kg）" : "バーのみ"
        }
        var s = "片側: \(b.perSide.map { SetFormatting.weightString($0) }.joined(separator: " + "))"
        if b.remainder > 0 { s += "（端数 \(SetFormatting.weightString(b.remainder))kg）" }
        return s
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
                } else if measurement == .bodyweight {
                    // 符号付き（−=補助 / 0=自重 / ＋=加重）。テンキーに±が無いため標準キーボードで受ける。
                    LabeledContent("加重(kg・補助は−)") { TextField("0", text: $weightText).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing) }
                    LabeledContent("回数") { TextField("回数", text: $repsText).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
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
                        // 不正値（負・非有限）は採用せず、分*60 のオーバーフローも防ぐ。
                        if isCardio {
                            if let km = Double(distanceText.replacingOccurrences(of: ",", with: ".")), km.isFinite, km >= 0 {
                                set.distanceKm = km
                            }
                            if let m = Int(minutesText), m >= 0 { set.durationSeconds = min(m, 100_000) * 60 }
                        } else if isTime {
                            if let s = Int(durationText), s >= 0 { set.durationSeconds = s }
                        } else {
                            // 自重（符号付き: −=補助）は負値を許可。通常ウェイトは0以上のみ。
                            if let w = Double(weightText.replacingOccurrences(of: ",", with: ".")), w.isFinite,
                               w >= 0 || measurement == .bodyweight {
                                set.weight = w
                            }
                            if let r = Int(repsText), r >= 0 { set.reps = r }
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
