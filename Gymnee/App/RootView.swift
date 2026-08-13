import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case workout, calendar, character, social, other
}

/// アプリのルート。サインインウォールは置かず、未サインインなら**ゲスト（ローカル）で即開始**する（§5）。
/// いきなりサインイン要求は価値を体験する前の離脱要因になるため、サインインは
/// ソーシャル/AI計画/設定のバックエンド必須導線（BackendSignInButtons 等）から後付けする。
/// 起動直後は「記録」タブ（記録開始の入口）を表示する。
struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppErrorCenter.self) private var errors
    @Environment(NotificationService.self) private var notifications
    @Environment(LocalSyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var context
    @State private var selection: AppTab = .workout
    /// 「その他」タブのナビゲーションスタック。ショップを外（通知）から開くため、
    /// パスをルート側で持つ。
    @State private var otherPath: [AppRoute] = []
    @AppStorage("gymnee.setupDone") private var setupDone = false
    /// ストア退避（GymneeSchema.makeContainer の復旧パス）が起きた直後の一度きりの通知。
    @AppStorage(GymneeSchema.recoveryPendingKey) private var storeRecoveryPending = false
    #if DEBUG
    @State private var debugWorkout: Workout?
    #endif

    var body: some View {
        signedInContent
            .task {
                // DEBUG デモのサインイン（ユウト）を先に通し、それ以外はゲストで自動開始。
                await runDebugHarnessIfNeeded()
                // 再インストール直後は Keychain にバックエンドセッションが残っていることがある。
                // 復元前にゲストを発行するとその窓の記録が新ゲスト uid の孤児になるため、
                // 復元（成功/失敗）を待ってから判定する（restore はシングルフライトで多重実行されない）。
                if !auth.isSignedIn, auth.hasPersistedBackendSession {
                    await auth.restoreBackendSession()
                }
                ensureGuestSession()
                // 「同期履歴はあるのに手元が空」＝ストアが作り直された、と見てフル取得し直す。
                // 復旧フラグを条件にすると、フラグがアラート表示で消費されたあとの端末を救えない
                // （実際にそれで復帰できなかった）。状態そのものを毎回見る。
                await SyncRecovery.recoverIfNeeded(
                    userId: auth.currentUserId,
                    isSignedIn: auth.isPermanentAccount,
                    context: context,
                    sync: syncEngine
                )
                // カレンダーをタブから外したため、Widget スナップショットと通知予約は
                // 画面到達に依存させず起動時にも回す（§6.10）。
                syncPlatformOnLaunch()
            }
            // サインアウト後もウォールへ戻さず、新しいゲストで続行（再サインインは設定から）。
            .onChange(of: auth.isSignedIn) { _, signedIn in
                if !signedIn { ensureGuestSession() }
            }
            // テキスト入力以外をタップしたらキーボードを閉じる（全画面共通の操作規約）。
            .onAppear { KeyboardDismissal.installIfNeeded() }
            .alert("エラー", isPresented: Bindable(errors).isPresented, presenting: errors.message) { _ in
                Button("OK", role: .cancel) {}
            } message: { msg in
                Text(msg)
            }
            // ストア退避が起きた（＝端末上の記録を読み込めず新しい保存領域で起動した）ことの通知。
            // 黙って空の状態を見せると「記録が消えた」動揺と誤った再入力を招くため、事実と窓口を一度だけ示す。
            .alert("データの読み込みに問題が発生しました", isPresented: $storeRecoveryPending) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("端末内の記録を読み込めなかったため、保存領域を作り直しました。元のデータは端末内に退避してあります。サインイン済みの場合、同期済みの記録は自動的に復元されます。心当たりのない場合はお問い合わせください。")
            }
    }

    /// 起動時の Widget スナップショット更新＋通知予約。許諾ダイアログはここでは出さない
    /// （プリパーミッションはカレンダー画面が担当する）。
    private func syncPlatformOnLaunch() {
        guard let uid = auth.currentUserId else { return }
        PlatformSync.run(userId: uid, context: context, notifications: notifications)
    }

    /// 未サインインならゲスト（ローカル）セッションを自動開始する。
    /// 記録は端末に保存され、後からのサインイン時に IdentityAdoptionPolicy が引き継ぐ。
    private func ensureGuestSession() {
        guard !auth.isSignedIn else { return }
        auth.signIn(displayName: "")
    }

    @ViewBuilder
    private var signedInContent: some View {
        #if DEBUG
        if let screen = DebugSupport.screen, let uid = auth.currentUserId {
            debugScreen(screen, userId: uid)
        } else {
            mainTabs
        }
        #else
        mainTabs
        #endif
    }

    private func runDebugHarnessIfNeeded() async {
        #if DEBUG
        guard DebugSupport.demoRequested else { return }
        // 招待リンク受信の再現（-gymneeInvite <uuid>）。サインイン前に保留させ、
        // 実際のコールドスタート（onOpenURL → 保留 → ソーシャルで消費）と同じ経路を通す。
        if let inviter = DebugSupport.inviteUserId {
            UserDefaults.standard.set(inviter.uuidString, forKey: InviteLink.pendingDefaultsKey)
        }
        if !auth.isSignedIn { auth.signIn(displayName: "ユウト") }
        guard let uid = auth.currentUserId else { return }
        DemoData.seedIfNeeded(context, userId: uid)
        if DebugSupport.screen == "logger", debugWorkout == nil {
            debugWorkout = DemoData.makeLoggerWorkout(context, userId: uid)
        }
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private func debugScreen(_ name: String, userId: UUID) -> some View {
        switch name {
        case "profile": NavigationStack { ProfileView(userId: userId).gymneeNavigationDestinations(userId: userId) }
        case "settings": NavigationStack { SettingsView() }
        case "social": SocialFeedView()
        case "friends": SocialFeedView(openFriends: true)
        case "shop": ShopView()
        case "analytics": NavigationStack { AnalyticsView(userId: userId) }
        case "muscle":
            // 人体図の部位タップ先（種目のベスト一覧）の検証用。デモで最も記録が多い部位を開く。
            debugMuscleSheet(userId: userId)
        case "history": NavigationStack { HistoryView(userId: userId) }
        case "body": NavigationStack { BodyMetricsView(userId: userId) }
        case "photos": NavigationStack { ProgressPhotosView(userId: userId) }
        case "composer":
            // 投稿コンポーザ（プレビュー）の検証用：デモの最新完了ワークアウト。
            if let w = latestCompletedWorkout(userId: userId) {
                PostComposerView(workout: w, baseEntry: debugPostEntry(w, userId: userId))
            }
        case "share":
            // 共有画像（PostCardView(.share)＝種目ごとの全セット展開）の検証用。
            if let w = latestCompletedWorkout(userId: userId) {
                SharePreviewSheet(entry: debugPostEntry(w, userId: userId),
                                  photo: PhotoStore.load(w.localPhotoFilename))
            }
        case "workout", "record": RecordView()
        case "calendar": CalendarHomeView()
        case "character": CharacterRoomView(userId: userId)
        // タブバー込みのレイアウト検証用。単体表示では safe area にタブバーが乗らず、
        // ボタンとタブバーの重なり（実機で発覚した不具合）を再現できないため。
        case "character-tab":
            TabView(selection: .constant("character")) {
                Tab("記録", systemImage: "dumbbell.fill", value: "record") { Color.clear }
                Tab("カレンダー", systemImage: "calendar", value: "calendar") { Color.clear }
                Tab("育成", systemImage: "figure.strengthtraining.traditional", value: "character") {
                    CharacterRoomView(userId: userId)
                }
                Tab("ソーシャル", systemImage: "person.2.fill", value: "social") { Color.clear }
                Tab("その他", systemImage: "ellipsis", value: "other") { Color.clear }
            }
        // ドット絵の一覧。絵を足したり直したりしたとき、崩れをスクショ 1 枚で確認する用。
        // コーチとのチャット（部屋でコーチをタップしたときに出るもの）。
        case "coach": CoachChatView(userId: userId)
        // 見た目シート（色 / 髪型 / アクセ / ペット）。部屋から開くのと同じもの。
        // タブ指定つきは IAP の審査用スクリーンショットを撮るために使う
        // （`-gymneeScreen appearance-pet` など。1 商品につき 1 枚が必要）。
        case "appearance": debugAppearanceSheet(tab: .hair)
        case "appearance-color": debugAppearanceSheet(tab: .color)
        case "appearance-accessory": debugAppearanceSheet(tab: .accessory)
        case "appearance-pet": debugAppearanceSheet(tab: .pet)
        // 完了直後の祝い（育成タブで出るもの）。デモの最新完了ワークアウトで組み立てる。
        case "growth":
            CharacterRoomView(userId: userId)
                .onAppear {
                    // レベルアップした回の見え方を確認する用の作り物。
                    WorkoutGrowth.Pending.save(WorkoutGrowth.Gain(
                        exp: 186, energy: 48,
                        levelBefore: CharacterProgress.level(totalExperience: 380),
                        levelAfter: CharacterProgress.level(totalExperience: 566),
                        stageBefore: .rookie, stageAfter: .rookie,
                        muscles: [
                            .init(muscle: .chest, volumeKg: 4200),
                            .init(muscle: .arms, volumeKg: 1800),
                        ],
                        prCount: 1,
                        nextStage: CharacterProgress.nextStage(level: 4, prCount: 1, weeklyStreakWeeks: 1)
                    ))
                    NotificationCenter.default.post(name: .gymneeShowCharacter, object: nil)
                }
        case "pixelart": PixelArtGallery(section: .character)
        case "pixelart-items": PixelArtGallery(section: .items)
        case "pixelart-room": PixelArtGallery(section: .room)
        case "pixelart-pets": PixelArtGallery(section: .pets)
        case "other": OtherTabView(userId: userId, path: $otherPath)
        case "summary":
            // 完了サマリーの検証用：デモの最新完了ワークアウトを表示（週次はゴール達成状態）。
            if let w = latestCompletedWorkout(userId: userId) {
                WorkoutSummaryView(workout: w, streak: 3, weeklyCount: 3,
                                   postEntry: debugPostEntry(w, userId: userId),
                                   onClose: {})
            }
        case "logger":
            if let w = debugWorkout {
                NavigationStack { RecordContent(userId: userId, resuming: w) }
            } else {
                RecordView()
            }
        default: mainTabs
        }
    }

    /// 見た目シートのハーネス。所持ゼロ・価格は控えの値で、購入できる状態の見え方を確認する。
    @ViewBuilder
    private func debugAppearanceSheet(tab: AppearanceSheet.Tab) -> some View {
        AppearanceSheet(
            build: CharacterBuild(girth: .normal, arm: .thick, leg: .thick),
            stage: .challenger,
            equipped: [:],
            currentSkinId: SkinCatalog.defaultSkinId,
            currentHairId: PixelHairArt.defaultStyleId,
            currentAccessoryId: "glasses",
            currentPetId: PetCatalog.noneId,
            isOwned: { _, _ in false },
            priceText: { kind, id in
                StoreCatalog.entry(kind: kind, contentID: id)?.fallbackPrice ?? "—"
            },
            isStoreReachable: true,
            canPurchase: { _, _ in true },
            onSelectSkin: { _ in }, onSelectHair: { _ in },
            onSelectAccessory: { _ in }, onSelectPet: { _ in },
            onPurchase: { _, _ in false }, onRestore: { nil },
            onAppearReload: {},
            initialTab: tab
        )
    }

    /// composer ハーネス用：最新完了ワークアウトのフィード項目。
    private func debugPostEntry(_ w: Workout, userId: UUID) -> FeedEntry {
        let completed = (try? context.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.userId == userId && $0.completedAt != nil })
        )) ?? []
        let wid = w.id
        let prCount = (try? context.fetchCount(
            FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.workoutId == wid })
        )) ?? 0
        return FeedBuilder.workoutEntry(
            w, prCount: prCount,
            activeDays: completed.map { $0.completedAt ?? $0.date },
            visibility: .friends, isPublished: false,
            ownerName: "ユウト"
        )
    }

    /// muscle ハーネス用：デモで最も記録が多い部位の詳細シート。
    @ViewBuilder
    private func debugMuscleSheet(userId: UUID) -> some View {
        let workouts = (try? context.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.userId == userId && $0.completedAt != nil })
        )) ?? []
        let entries = MuscleLoadInputs.sessionEntries(from: workouts)
        let fatigue = MuscleFatigue.statuses(entries: entries)
        let weekly = WeeklyMuscleLoad.statuses(entries: entries)
        // 直近に鍛えた部位＝デモで確実に記録がある部位を開く。
        let target = fatigue.compactMap { s in s.lastTrained.map { (s.muscle, $0) } }
            .max { $0.1 < $1.1 }?.0 ?? .chest
        MuscleDetailSheet(
            muscle: target,
            userId: userId,
            status: fatigue.first { $0.muscle == target }
                ?? MuscleFatigue.Status(muscle: target, lastTrained: nil, lastSetCount: 0, fatigue: 0),
            weekly: weekly.first { $0.muscle == target }
                ?? WeeklyMuscleLoad.Status(muscle: target, sets: 0, targetSets: WeeklyMuscleLoad.targetSets(for: target))
        )
    }

    /// summary ハーネス用：デモの最新完了ワークアウト。
    private func latestCompletedWorkout(userId: UUID) -> Workout? {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.userId == userId && $0.completedAt != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor)) ?? []).first
    }
    #endif

    /// 初回サインイン後の初期設定を一度だけ提示（DEBUGデモ時は出さない）。
    private var shouldShowSetup: Bool {
        #if DEBUG
        if DebugSupport.demoRequested { return false }
        #endif
        return auth.isSignedIn && !setupDone
    }

    private var mainTabs: some View {
        TabView(selection: $selection) {
            RecordView()
                .tabItem { Label("記録", systemImage: "dumbbell.fill") }
                .tag(AppTab.workout)

            CalendarHomeView()
                .tabItem { Label("カレンダー", systemImage: "calendar") }
                .tag(AppTab.calendar)

            characterTab
                .tabItem { Label("育成", systemImage: "figure.strengthtraining.traditional") }
                .tag(AppTab.character)

            SocialFeedView()
                .tabItem { Label("ソーシャル", systemImage: "person.2.fill") }
                .tag(AppTab.social)

            otherTab
                .tabItem { Label("その他", systemImage: "ellipsis") }
                .tag(AppTab.other)
        }
        .tint(Theme.energy)
        .fullScreenCover(isPresented: Binding(get: { shouldShowSetup }, set: { _ in })) {
            SetupOnboardingView()
        }
        // 招待リンク経由の起動（未サインイン→サインイン完了後を含む）: 保留中の招待が
        // あればソーシャルタブへ。招待者プロフィールの表示は SocialFeedView 側が保留を消費して行う。
        .onAppear {
            if UserDefaults.standard.string(forKey: InviteLink.pendingDefaultsKey) != nil {
                selection = .social
            }
        }
        // 記録のキャンセルからカレンダーへ。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeShowCalendar)) { _ in
            selection = .calendar
        }
        // 記録の完了サマリーを閉じたら育成タブへ。育った本人の前で、この1回の結果を出す。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeShowCharacter)) { _ in
            selection = .character
        }
        // 計画/予定の「開始」から記録タブへ（RecordView 側が当該ワークアウトを再開する）。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeStartWorkout)) { _ in
            selection = .workout
        }
        // 通知タップのルーティング（type に応じて該当タブへ）。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeOpenDestination)) { note in
            switch note.userInfo?["type"] as? String {
            case "reaction", "follow", "invite": selection = .social
            case "workout": selection = .workout
            // 週次まとめはカレンダーで振り返る。
            case "recap": selection = .calendar
            case "shop":
                otherPath = [.shop]
                selection = .other
            default: break
            }
        }
    }

    @ViewBuilder
    private var characterTab: some View {
        if let uid = auth.currentUserId {
            CharacterRoomView(userId: uid)
        } else {
            EmptyStateView(systemImage: "figure.strengthtraining.traditional", title: "未ログイン")
        }
    }

    @ViewBuilder
    private var otherTab: some View {
        if let uid = auth.currentUserId {
            OtherTabView(userId: uid, path: $otherPath)
        } else {
            EmptyStateView(systemImage: "ellipsis", title: "未ログイン")
        }
    }
}

// MARK: - キーボード外タップで閉じる（全画面共通）

/// UIWindow にキャンセルしないタップ認識を1度だけ仕込み、テキスト入力ビュー以外への
/// タップで `endEditing` する。SwiftUI 標準ではタップでキーボードが閉じず、フォーム入力後に
/// 閉じる手段が無い（報告: 投稿コメント ほか全テキスト入力）。
@MainActor
enum KeyboardDismissal {
    private static var installed = false
    private static let delegate = TouchFilterDelegate()

    static func installIfNeeded() {
        guard !installed else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first })
            .first
        else { return }
        let tap = UITapGestureRecognizer(target: window, action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false   // ボタン等のタップは素通しし、キーボードだけ閉じる
        tap.requiresExclusiveTouchType = false
        tap.delegate = delegate
        window.addGestureRecognizer(tap)
        installed = true
    }

    /// テキスト入力ビュー自身（カーソル移動・別フィールドへのフォーカス移動）への
    /// タップでは発火させないフィルタ。
    private final class TouchFilterDelegate: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view: UIView? = touch.view
            while let v = view {
                if v is UITextInput { return false }
                view = v.superview
            }
            return true
        }
    }
}
