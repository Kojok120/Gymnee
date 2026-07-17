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
    /// チェックインフロー（フルスクリーン）。完了は .gymneeDidCheckIn 経由でゲートが開く。
    @State private var showCheckIn = false
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
                        onCheckIn: { showCheckIn = true },
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
        // ゲートからのチェックイン。cover はゲートの外（ここ）に付ける：完了通知で
        // ゲートが RecordContent に差し替わっても提示元が消えず、閉じアニメーションが乱れない。
        .fullScreenCover(isPresented: $showCheckIn) { CheckInView() }
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
    /// チェックインフローを開く（ジム到着時の入口。完了後は自動で記録が始まる）。
    var onCheckIn: () -> Void = {}
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
                    Spacer(minLength: 0)
                    // ブランドヒーロー＋開始導線（タイル＋行カード）を画面中央にまとめる。
                    // 記録タブは起動直後のトップ＝アプリの顔なので、見出しは「Gymnee」を大きく出す。
                    VStack(spacing: Theme.Spacing.xl) {
                        VStack(spacing: Theme.Spacing.md) {
                            ZStack {
                                Circle().fill(Theme.lime.opacity(0.16)).frame(width: 96, height: 96)
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.system(size: 46, weight: .bold))
                                    .foregroundStyle(Theme.lime)
                            }
                            Text("Gymnee")
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Text("準備ができたら開始しましょう").font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }
                        VStack(spacing: Theme.Spacing.md) {
                            // 入口は横並びツインのタイル：ジム到着時はチェックイン（完了で自動的に
                            // 記録開始）、それ以外（自宅トレ等）は記録を直接開始。主 CTA のライムは記録側。
                            HStack(spacing: Theme.Spacing.md) {
                                gateTile(title: "チェックイン", caption: "ジムに着いたら",
                                         icon: "door.right.hand.open", primary: false, action: onCheckIn)
                                gateTile(title: "記録を開始", caption: "今すぐ始める",
                                         icon: "play.fill", primary: true, action: onStart)
                            }
                            // 補助導線は全幅の行カード（テキストリンクだと見落とされ押しづらいため）。
                            // テンプレは新規ユーザー（完了記録なし）だけに出す活性化導線。
                            if showTemplates {
                                gateRow(title: "テンプレから始める", icon: "square.grid.2x2", action: onTemplates)
                            }
                            // 履歴リンクは単発クロージャ型：RecordContent が push 経由(カレンダー編集/
                            // ワークアウト詳細)で開かれても pushed view 上の navigationDestination(for:) に
                            // 依存せず確実に遷移する（iOS 26.5 で子リンクが解決されない問題の回避。
                            // List/ForEach 内ではないのでハングもしない）。
                            NavigationLink {
                                HistoryView(userId: userId)
                            } label: {
                                gateRowLabel(title: "これまでの記録を見る", icon: "list.bullet.rectangle")
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                // 中身が画面より短ければ Spacer が中央へ寄せ、長ければスクロール。
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .background(Theme.bg0)
        }
        // 記録タブは起動直後のトップ＝アプリの顔。ナビバーは隠し、中央のブランドヒーローに任せる。
        .toolbar(.hidden, for: .navigationBar)
    }

    /// 入口タイル（チェックイン/記録を開始）。大きな面で押しやすく、押下で沈み込む。
    private func gateTile(title: String, caption: String, icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(primary ? Theme.onLime : Theme.lime)
                VStack(spacing: 1) {
                    Text(title).font(.headline)
                        .foregroundStyle(primary ? Theme.onLime : Theme.textPrimary)
                    Text(caption).font(.caption2)
                        .foregroundStyle(primary ? Theme.onLime.opacity(0.75) : Theme.textTertiary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
            .background(primary ? Theme.limeFill : Theme.bg1,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.bg3, lineWidth: 1)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// 補助導線の行カード（アイコン＋タイトル＋シェブロン）。
    private func gateRowLabel(title: String, icon: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .contentShape(Rectangle())
    }

    private func gateRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { gateRowLabel(title: title, icon: icon) }
            .buttonStyle(PressableButtonStyle())
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
    @State private var editingExercise: Exercise?
    @State private var editingSet: ExerciseSet?
    @State private var keypad: KeypadRequest?
    @State private var showOnboarding = false
    @State private var showCancelConfirm = false
    @State private var showMemo = false
    /// 録画中の暫定PRスパーク（その場の「更新ペース！」表示・非永続。確定は完了時）。
    @State private var prSpark: PRSpark?
    /// フリーの選択中カテゴリタブ（③。よくやる/部位でカード一覧をフィルタ）。
    @State private var selectedTab: RecordCategoryTab = .group(.chest)
    /// 初期タブ決定済みフラグ（rebuild のたびに選択を上書きしない）。
    @State private var tabInitialized = false
    /// 「よくやる種目」（直近60日の使用回数トップ10）。rebuildCatalog で再計算・キャッシュ。
    @State private var frequentExercises: [Exercise] = []
    /// 部位ごとの頻度トップ3（未カスタマイズタブの既定シェルフ用）。
    @State private var groupRankedIds: [MuscleGroup: [UUID]] = [:]
    /// 同名重複を除いた種目の解決表（id → Exercise）。シェルフ表示・削除済み種目のフィルタに使う。
    @State private var exercisesById: [UUID: Exercise] = [:]
    /// 正規化名 → 正準 id（定番プリセット名の解決・重複 id の正準化用）。
    @State private var idsByName: [String: UUID] = [:]
    /// デコード済みのカスタムシェルフ（保存は shelvesJSON へ）。
    @State private var shelves = ExerciseShelves()
    /// 「その他」ピッカーを開いている対象タブ。
    @State private var pickingTarget: ShelfPickerTarget?

    @AppStorage("gymnee.recordShelves") private var shelvesJSON = ""

    @AppStorage("gymnee.recordOnboardingShown") private var onboardingShown = false
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.friends.rawValue
    // 破損値は安全側（friends）へ。公開面の fail-closed 方針に合わせ public フォールバックにしない。
    private var defaultVisibility: Visibility { Visibility(rawValue: defaultVisibilityRaw) ?? .friends }

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
            if mode == .free { categoryTabBar }
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
        // 「その他」カード: その部位の種目ピッカー。選んだ/作った種目を開いているタブへ永続追加する。
        .sheet(item: $pickingTarget) { target in
            ExercisePickerView(
                exercises: pickerExercises,
                group: target.group,
                onSelect: { ex in addToShelf(ex, group: target.group) }
            )
        }
        // 種目編集（器具・計測タイプ変更）は centers の既定値に影響するため、閉じたらキャッシュを捨てる。
        // 種目編集（器具・計測タイプ変更）は centers の既定値に、部位・名前変更はタブの既定
        // シェルフ/解決表に影響するため、閉じたらキャッシュ破棄＋カタログ再構築する
        // （rebuild は種目数変化でしか走らないため、ここで明示的に呼ぶ）。
        .sheet(item: $editingExercise, onDismiss: {
            centersCache.values.removeAll()
            rebuildCatalog()
        }) { ex in ExerciseInspectorView(exercise: ex, userId: userId) }
        .sheet(item: $editingSet) { set in
            EditSetSheet(set: set, onCommit: { commitSetEdit(set) }, onDelete: { deleteSet(set) })
        }
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
                    weeklyCount: weeklyActiveDays,
                    // 投稿は明示同意（fail-closed）。バックエンド未接続・未サインインでは出さない。
                    postVisibilityLabel: (defaultVisibility == .private ? Visibility.friends : defaultVisibility).label,
                    onPost: (sync.isRemoteEnabled && auth.isPermanentAccount) ? { publishConsented(w) } : nil,
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
            shelves = ExerciseShelves.decode(from: shelvesJSON)
            discardAbandonedDrafts()
            if let resuming, activeWorkout == nil {
                activeWorkout = resuming
                modeInitialized = true
            } else {
                initializeModeIfNeeded()
                if !onboardingShown { showOnboarding = true }
            }
        }
        // フリーのカードカタログは種目数が変わった時だけ作り直す（毎描画の関連走査を避ける）。
        .task(id: allExercises.count) { rebuildCatalog() }
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

    // MARK: - ① モードバー

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
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - ③ カテゴリタブ

    /// カテゴリタブ（フリーのみ・常時表示・横スクロール）。タップで下のカード一覧をフィルタする
    /// （旧: 部位Menu によるスクロールジャンプ → 居酒屋オーダーUI式のタブフィルタへ変更）。
    private var categoryTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                if !frequentExercises.isEmpty {
                    tabChip(.frequent, label: "よくやる")
                }
                ForEach(MuscleGroup.allCases, id: \.self) { mg in
                    tabChip(.group(mg), label: mg.label)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private func tabChip(_ tab: RecordCategoryTab, label: String) -> some View {
        let selected = selectedTab == tab
        return Button { selectedTab = tab } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 6)
                .background(selected ? Theme.textPrimary : Theme.bg1, in: Capsule())
                .foregroundStyle(selected ? Theme.bg0 : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var modeLabel: String {
        switch mode {
        case .free: return "フリー"
        case .plan: return todayPlan.map { "本日の計画: \($0.title)" } ?? "本日の計画"
        case .routine(let id): return routines.first { $0.id == id }?.name ?? "カスタムセット"
        }
    }

    // MARK: - ② 記録ログ

    /// 記録ログのグループ（1種目=1行）。行順は orderIndex 昇順＝初回セット記録順で安定させる
    /// （セット追加で行が飛ばない）。セットは createdAt 昇順＝タップ順。
    private var logGroups: [(we: WorkoutExercise, sets: [ExerciseSet])] {
        (activeWorkout?.exercises ?? [])
            .filter { !$0.sets.isEmpty }
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { ($0, $0.sets.sorted { $0.createdAt < $1.createdAt }) }
    }

    /// セッションの総セット数（自動スクロールのトリガ判定に使う）。
    private var loggedSetCount: Int {
        activeWorkout?.exercises.reduce(0) { $0 + $1.sets.count } ?? 0
    }

    /// 最後に記録されたセット（取り消し対象・lime 強調・自動スクロール先）。
    private var newestSet: ExerciseSet? {
        activeWorkout?.exercises.flatMap(\.sets).max { $0.createdAt < $1.createdAt }
    }

    /// ② 記録ログ。種目でグルーピングし、セットは折返しチップで全量見せる（横スクロールなし）。
    /// チップタップ＝編集シート（削除もそこから）。ヘッダー右上の「取り消し」＝直前の1セット削除。
    @ViewBuilder
    private var logStrip: some View {
        let groups = logGroups
        if groups.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle").font(.caption)
                Text("記録するとここに溜まります").font(.caption)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: 52)
            .background(Theme.bg1)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("記録ログ").font(.caption).foregroundStyle(Theme.textTertiary)
                    Spacer()
                    // 誤タップで余計なセットが記録された直後のミスを1タップで戻す。
                    Button {
                        if let last = newestSet { deleteSet(last) }
                    } label: {
                        Label("取り消し", systemImage: "arrow.uturn.backward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            ForEach(groups, id: \.we.id) { group in
                                GroupedLogRow(
                                    exerciseName: group.we.exercise?.name ?? "種目",
                                    sets: group.sets,
                                    latestSetId: newestSet?.id,
                                    onTapSet: { editingSet = $0 }
                                )
                                .id(group.we.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.sm)
                    }
                    // 新しいセットが記録されたら、その種目の行へ自動スクロール（削除では動かさない）。
                    .onChange(of: loggedSetCount) { old, new in
                        guard new > old, let target = newestSet?.workoutExercise?.id else { return }
                        withAnimation(.snappy) { proxy.scrollTo(target, anchor: .bottom) }
                    }
                    // 下書き再開時：最後に記録した行が見える位置から始める。
                    .onAppear {
                        if let target = newestSet?.workoutExercise?.id {
                            proxy.scrollTo(target, anchor: .bottom)
                        }
                    }
                }
                .frame(height: 150)
            }
            .background(Theme.bg1)
        }
    }

    // MARK: - ④ カード

    @ViewBuilder
    private var cardsArea: some View {
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
        // タブ切替でスクロール位置を先頭へ戻す（フィルタなので前タブの位置を引き継がない）。
        .id(selectedTab)
    }

    /// フリー：選択中タブの種目カード。部位タブは「シェルフ」（既定=頻度トップ3→定番補完。
    /// ユーザーが追加/削除でカスタマイズ可）＋末尾の「その他」カード。
    @ViewBuilder
    private var freeCardsBody: some View {
        switch selectedTab {
        case .frequent:
            cardGrid(frequentExercises.map { CardSpec(exercise: $0, routineExercise: nil, explicit: nil) })
        case .group(let mg):
            let shelf = shelfExercises(for: mg)
            if shelf.isEmpty {
                Text("このタブに種目がありません。「その他」から追加できます。")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
            shelfCardGrid(shelf.map { CardSpec(exercise: $0, routineExercise: nil, explicit: nil) }, group: mg)
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

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: Theme.Spacing.md), GridItem(.flexible(), spacing: Theme.Spacing.md)]
    }

    private func cardGrid(_ specs: [CardSpec]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: Theme.Spacing.md) {
            cardCells(specs, onRemove: nil)
        }
    }

    /// 部位タブのグリッド：シェルフの種目カード＋末尾の「その他」カード。カードは名前部の長押しでタブから外せる。
    private func shelfCardGrid(_ specs: [CardSpec], group: MuscleGroup) -> some View {
        LazyVGrid(columns: gridColumns, spacing: Theme.Spacing.md) {
            cardCells(specs, onRemove: { removeFromShelf($0, group: group) })
            otherCard(group)
        }
    }

    @ViewBuilder
    private func cardCells(_ specs: [CardSpec], onRemove: ((Exercise) -> Void)?) -> some View {
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
                    onOpen: { editingExercise = spec.exercise },
                    onRemove: onRemove.map { remove in { remove(spec.exercise) } }
                )
            }
    }

    /// 「その他」カード。タップで全種目ピッカーを開き、選んだ種目をこのタブへ永続追加する。
    private func otherCard(_ group: MuscleGroup) -> some View {
        Button { pickingTarget = ShelfPickerTarget(group: group) } label: {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.title3).foregroundStyle(Theme.textSecondary)
                Text("その他").font(.caption.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text("種目を探す・追加").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(Theme.bg2, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.textTertiary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - シェルフ（タブごとの表示種目）

    /// タブに表示する種目。カスタマイズ済みならそれ（削除済み種目は読み時に除外）、
    /// 未カスタマイズなら既定（部位別頻度トップ3→定番プリセット補完）。
    private func shelfExercises(for group: MuscleGroup) -> [Exercise] {
        let ids: [UUID]
        if let stored = shelves.shelf(for: group) {
            ids = ExerciseShelf.resolve(stored: stored, existing: Set(exercisesById.keys))
        } else {
            let standards = ExerciseShelf.standardNames[group, default: []]
                .compactMap { idsByName[$0.lowercased()] }
            ids = ExerciseShelf.defaultIds(frequencyRanked: groupRankedIds[group] ?? [], standards: standards)
        }
        return ids.compactMap { exercisesById[$0] }
    }

    private func addToShelf(_ exercise: Exercise, group: MuscleGroup) {
        // 同名別id の重複がある種目は、表示解決に使う正準の id に揃えてから保存する
        // （非正準の id を保存すると resolve で除外され「追加したのに出ない」になる）。
        let id = idsByName[exercise.normalizedName] ?? exercise.id
        var updated = shelves
        updated.add(id, to: group, current: shelfExercises(for: group).map(\.id))
        shelves = updated
        shelvesJSON = updated.encoded()
    }

    private func removeFromShelf(_ exercise: Exercise, group: MuscleGroup) {
        var updated = shelves
        updated.remove(exercise.id, from: group, current: shelfExercises(for: group).map(\.id))
        shelves = updated
        shelvesJSON = updated.encoded()
    }

    /// ピッカーに渡す全種目（同名重複を解決済み・名前順）。
    private var pickerExercises: [Exercise] {
        exercisesById.values.sorted { $0.name < $1.name }
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

    /// フリーのカード表示に使う種目カタログの再構築（種目数が変わった時だけ）。
    /// 同名別id の重複（プリセットが同期で増殖するケース等）は履歴のある方を優先して1つにまとめ、
    /// 「よくやる」ランキング・部位別頻度・解決表（id/名前）を作る。
    private func rebuildCatalog() {
        let recent = allExercises.filter { ex in
            ex.workoutExercises.contains { $0.workout?.userId == userId && $0.workout?.completedAt != nil && !$0.sets.isEmpty }
        }
        var seenIds = Set<UUID>()
        var seenNames = Set<String>()
        var ordered: [Exercise] = []
        func addIfNew(_ ex: Exercise) {
            let nameKey = ex.normalizedName
            guard !seenNames.contains(nameKey), seenIds.insert(ex.id).inserted else { return }
            seenNames.insert(nameKey)
            ordered.append(ex)
        }
        // 履歴のある種目を先に処理する（重複時に記録済みの id を正準として残す）。
        for ex in recent { addIfNew(ex) }
        for ex in allExercises { addIfNew(ex) }

        exercisesById = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        idsByName = Dictionary(ordered.map { ($0.normalizedName, $0.id) }, uniquingKeysWith: { first, _ in first })

        // 「よくやる種目」: dedupe 済みの ordered を対象に、完了ワークアウトの日付を集計してランク。
        let usage: [UUID: [Date]] = Dictionary(uniqueKeysWithValues: ordered.compactMap { ex in
            let dates = ex.workoutExercises.compactMap { we -> Date? in
                guard let w = we.workout, w.userId == userId, let done = w.completedAt, !we.sets.isEmpty else { return nil }
                return done
            }
            return dates.isEmpty ? nil : (ex.id, dates)
        })
        let rankedIds = FrequentExerciseRanker.rank(usage: usage, asOf: .now)
        frequentExercises = rankedIds.compactMap { exercisesById[$0] }

        // 部位別の頻度トップ3（未カスタマイズタブの既定シェルフ用）。少数でも返す（minExercises: 0）。
        groupRankedIds = Dictionary(uniqueKeysWithValues: MuscleGroup.allCases.map { mg in
            let filtered = usage.filter { exercisesById[$0.key]?.muscleGroup == mg }
            return (mg, FrequentExerciseRanker.rank(usage: filtered, asOf: .now, limit: 3, minExercises: 0))
        })

        // 初期タブ：履歴があれば「よくやる」、無ければ胸。よくやるが消えた場合も部位へ退避。
        if !tabInitialized {
            selectedTab = frequentExercises.isEmpty ? .group(.chest) : .frequent
            tabInitialized = true
        } else if frequentExercises.isEmpty, selectedTab == .frequent {
            selectedTab = .group(.chest)
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
        // 完了時に feed_item は作らない（fail-closed）。公開はサマリーの「ソーシャルに投稿」
        // ボタン（publishConsented）を押した時だけ。押さなければ feed_item は存在せず＝非公開。
        showSummary = true
    }

    /// サマリーの「ソーシャルに投稿」: このワークアウトと当日の最大重量 PR を公開範囲付きで発行する。
    /// 公開範囲はユーザー既定（既定が「非公開」の場合は投稿の意図が成立しないためフレンドに昇格）。
    private func publishConsented(_ workout: Workout) {
        let vis: Visibility = defaultVisibility == .private ? .friends : defaultVisibility
        FeedPublisher.publishWorkout(
            workout, authorName: auth.session?.displayName, visibility: vis,
            isPermanentAccount: auth.isPermanentAccount, context: context, sync: sync
        )
        Task { await sync.syncNow(force: true) }
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

    /// 連続記録・週次進捗の元になる活動日（来店＋完了ワークアウト）。
    /// サマリーは finish() 後に出るため、いま完了したワークアウト自身も含まれる。
    private var activeDays: [Date] {
        let uid = userId
        let visits = (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.userId == uid }))) ?? []
        let completed = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.userId == uid && $0.completedAt != nil }))) ?? []
        return visits.map(\.visitedAt) + completed.map { $0.completedAt ?? $0.date }
    }

    private var currentStreak: Int {
        StreakCalculator.currentStreak(visitDays: activeDays, calendar: .current)
    }

    /// 今週のアクティブ日数（サマリーの週次ゴールタイル「3/5」の分子）。
    private var weeklyActiveDays: Int {
        StreakCalculator.weeklyVisitDays(visitDays: activeDays)
    }
}

// MARK: - カテゴリタブ

/// フリーのカテゴリタブ（③）。よくやる＋部位でカード一覧をフィルタする。
private enum RecordCategoryTab: Hashable {
    case frequent
    case group(MuscleGroup)
}

/// 「その他」ピッカーを開く対象タブ（sheet(item:) 用）。
private struct ShelfPickerTarget: Identifiable {
    let group: MuscleGroup
    var id: String { group.rawValue }
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
    /// タブ（シェルフ）からこの種目を外す。フリーの部位タブのみ渡される（nil＝メニュー非表示）。
    var onRemove: (() -> Void)? = nil

    /// 自重のみ（重量軸を出さない）。
    private var bodyweightOnly: Bool {
        exercise.measurementType == .bodyweight && exercise.loadMode == .none
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            topRuler
            nameBlock
            bottomRuler
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.md)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// 名前部（ウェイト/回数のルーラー以外）。タップ＝種目インスペクタ / 長押し＝タブから外す。
    /// contextMenu はカード全体でなく名前部に限定する（ルーラーの長押しキーパッドと競合するため）。
    @ViewBuilder private var nameBlock: some View {
        let base = VStack(spacing: 1) {
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
        if let onRemove {
            base.contextMenu {
                Button(role: .destructive, action: onRemove) {
                    Label("このタブから外す", systemImage: "minus.circle")
                }
            }
        } else {
            base
        }
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

// MARK: - ② ログ行（1種目=1行・折返しチップ）

private struct GroupedLogRow: View {
    let exerciseName: String
    /// createdAt 昇順のセット列。
    let sets: [ExerciseSet]
    /// セッション全体の最新セット（完了直後の1件だけ lime で強調）。
    let latestSetId: UUID?
    let onTapSet: (ExerciseSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(exerciseName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            FlowLayout(spacing: 6) {
                ForEach(sets) { set in
                    Button { onTapSet(set) } label: {
                        Text(set.detailText)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 3)
                            .background(set.id == latestSetId ? Theme.limeSoft : Theme.bg2,
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
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
    /// このセットを削除する（ログのチップから開いた時のみ渡す）。
    var onDelete: (() -> Void)? = nil

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
                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("このセットを削除", systemImage: "trash")
                    }
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
        .presentationDetents([.height(onDelete == nil ? 220 : 280)])
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
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 40)).foregroundStyle(Theme.lime)
            Text("タップで記録")
                .font(.title2.bold()).foregroundStyle(Theme.textPrimary)
            // 実際の種目カードを模した説明図（文字だけより一目で伝わる・ユーザー要望）。
            mockCard
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

    /// 種目カードの説明図（静的・タップ不可）。①重量スロット→②回数スロットの操作を番号で対応づける。
    private var mockCard: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                stepBadge("1")
                Text("重量をタップして固定").font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            mockRuler(values: ["57.5", "60", "62.5"], centerStyle: .armed)
            Text("ベンチプレス")
                .font(.caption.weight(.bold)).foregroundStyle(Theme.textPrimary)
            mockRuler(values: ["9", "10", "11"], centerStyle: .action)
            HStack(spacing: 6) {
                stepBadge("2")
                Text("回数をタップ → 1セット記録").font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.lime.opacity(0.35), lineWidth: 1)
        }
    }

    private enum MockCenterStyle { case armed, action }

    /// SlotRuler の見た目を模した3セル（中央＝選択状態）。
    private func mockRuler(values: [String], centerStyle: MockCenterStyle) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let isCenter = index == 1
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        isCenter ? (centerStyle == .armed ? Theme.limeFill : Theme.limeSoft) : Theme.bg2,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    )
                    .overlay {
                        if isCenter, centerStyle == .action {
                            RoundedRectangle(cornerRadius: Theme.Radius.sm).strokeBorder(Theme.lime.opacity(0.6), lineWidth: 1)
                        }
                    }
                    .foregroundStyle(
                        isCenter ? (centerStyle == .armed ? Theme.onLime : Theme.lime) : Theme.textSecondary
                    )
                    .opacity(isCenter ? 1 : 0.5)
            }
        }
    }

    private func stepBadge(_ num: String) -> some View {
        Text(num)
            .font(.caption.bold()).foregroundStyle(Theme.onLime)
            .frame(width: 20, height: 20).background(Theme.lime, in: Circle())
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
