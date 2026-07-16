import SwiftUI

enum AppTab: Hashable {
    case calendar, workout, social, analytics, other
}

/// アプリのルート。未ログインは Onboarding、ログイン済みはタブ骨格を表示する（§5）。
/// 起動直後は「記録」タブ（記録開始とチェックインの入口）を表示する。
struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppErrorCenter.self) private var errors
    @Environment(\.modelContext) private var context
    @State private var selection: AppTab = .workout
    @AppStorage("gymnee.setupDone") private var setupDone = false
    #if DEBUG
    @State private var debugWorkout: Workout?
    @State private var debugRoutine: Routine?
    #endif

    var body: some View {
        Group {
            if auth.isSignedIn {
                signedInContent
            } else {
                OnboardingView()
            }
        }
        .animation(.default, value: auth.isSignedIn)
        .task { await runDebugHarnessIfNeeded() }
        // テキスト入力以外をタップしたらキーボードを閉じる（全画面共通の操作規約）。
        .onAppear { KeyboardDismissal.installIfNeeded() }
        .alert("エラー", isPresented: Bindable(errors).isPresented, presenting: errors.message) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
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
        if DebugSupport.screen == "routine", debugRoutine == nil {
            debugRoutine = RoutineTemplates.create(RoutineTemplates.all[0], userId: uid, context: context)
            try? context.save()
        }
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private func debugScreen(_ name: String, userId: UUID) -> some View {
        switch name {
        case "addgym": AddGymView(userId: userId)
        case "checkin": CheckInView()
        case "profile": NavigationStack { ProfileView(userId: userId).gymneeNavigationDestinations(userId: userId) }
        case "settings": NavigationStack { SettingsView() }
        case "social": SocialFeedView()
        case "friends": SocialFeedView(openFriends: true)
        case "shop": ShopView()
        case "routine":
            if let r = debugRoutine {
                NavigationStack { RoutineEditorView(routine: r, editorContext: context) }
            } else {
                NavigationStack { RoutinesView(userId: userId) }
            }
        case "analytics": NavigationStack { AnalyticsView(userId: userId) }
        case "history": NavigationStack { HistoryView(userId: userId) }
        case "body": NavigationStack { BodyMetricsView(userId: userId) }
        case "photos": NavigationStack { ProgressPhotosView(userId: userId) }
        case "share":
            ShareCardEditorView(content: ShareCardContent(
                image: nil, gymName: "Gymnee 渋谷", streak: 3,
                prText: "PR 2", exerciseSummary: "胸・三頭 3種目",
                exerciseLines: [
                    ShareCardExerciseLine(name: "ベンチプレス", detail: "80kg × 8・3セット", isPR: true),
                    ShareCardExerciseLine(name: "インクラインダンベルプレス", detail: "28kg × 10・3セット", isPR: false),
                    ShareCardExerciseLine(name: "ケーブルクロスオーバー", detail: "20kg × 12・3セット", isPR: false),
                    ShareCardExerciseLine(name: "スカルクラッシャー", detail: "30kg × 10・3セット", isPR: true),
                    ShareCardExerciseLine(name: "プッシュアップ", detail: "自重 × 15・2セット", isPR: false),
                    ShareCardExerciseLine(name: "プランク", detail: "60秒・2セット", isPR: false),
                    ShareCardExerciseLine(name: "サイドレイズ", detail: "8kg × 15・3セット", isPR: false),
                ],
                stats: [
                    ShareCardStat(value: "7,470kg", label: "総量"),
                    ShareCardStat(value: "19", label: "セット"),
                    ShareCardStat(value: "52分", label: "時間"),
                ]
            ))
        case "workout", "record": RecordView()
        case "calendar": CalendarHomeView()
        case "other": OtherTabView(userId: userId)
        case "logger":
            if let w = debugWorkout {
                NavigationStack { RecordContent(userId: userId, resuming: w) }
            } else {
                RecordView()
            }
        default: mainTabs
        }
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

            SocialFeedView()
                .tabItem { Label("ソーシャル", systemImage: "person.2.fill") }
                .tag(AppTab.social)

            analyticsTab
                .tabItem { Label("分析", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.analytics)

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
        // チェックイン完了後は記録タブへ（今日の計画の「開始」導線を見せる）。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeDidCheckIn)) { _ in
            selection = .workout
        }
        // 完了サマリー「分析を見る」から分析タブへ。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeShowAnalytics)) { _ in
            selection = .analytics
        }
        // 記録のキャンセルからカレンダータブへ。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeShowCalendar)) { _ in
            selection = .calendar
        }
        // 計画/予定の「開始」から記録タブへ（RecordView 側が当該ワークアウトを再開する）。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeStartWorkout)) { _ in
            selection = .workout
        }
        // 通知タップのルーティング（type に応じて該当タブへ）。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeOpenDestination)) { note in
            switch note.userInfo?["type"] as? String {
            case "reaction", "friend_checkin", "follow", "invite": selection = .social
            // チェックイン導線は記録タブ（開始ゲート）にあるため、checkin 通知も記録タブへ。
            case "workout", "checkin": selection = .workout
            case "analytics": selection = .analytics
            case "recap": selection = .calendar
            case "shop": selection = .other
            default: break
            }
        }
    }

    @ViewBuilder
    private var analyticsTab: some View {
        if let uid = auth.currentUserId {
            NavigationStack { AnalyticsView(userId: uid) }
        } else {
            EmptyStateView(systemImage: "chart.bar", title: "未ログイン")
        }
    }

    @ViewBuilder
    private var otherTab: some View {
        if let uid = auth.currentUserId {
            OtherTabView(userId: uid)
        } else {
            EmptyStateView(systemImage: "ellipsis", title: "未ログイン")
        }
    }
}

// MARK: - キーボード外タップで閉じる（全画面共通）

/// UIWindow にキャンセルしないタップ認識を1度だけ仕込み、テキスト入力ビュー以外への
/// タップで `endEditing` する。SwiftUI 標準ではタップでキーボードが閉じず、フォーム入力後に
/// 閉じる手段が無い（報告: チェックインのメモ/合トレ相手 ほか全テキスト入力）。
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
