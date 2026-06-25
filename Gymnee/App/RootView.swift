import SwiftUI

enum AppTab: Hashable {
    case calendar, workout, social, analytics, other
}

/// アプリのルート。未ログインは Onboarding、ログイン済みはタブ骨格を表示する（§5）。
/// 中央の「チェックイン」タブは選択時にフルスクリーンのチェックインフローを起動する（§6.3）。
struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppErrorCenter.self) private var errors
    @Environment(\.modelContext) private var context
    @State private var selection: AppTab = .calendar
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
        if !auth.isSignedIn { auth.signIn(displayName: "デモ太郎") }
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
        case "friends": SocialFeedView(initialTab: 1)
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
                prText: "ベンチ 80kg", exerciseSummary: "胸・三頭 3種目"
            ))
        case "workout", "record": RecordView()
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
            CalendarHomeView()
                .tabItem { Label("カレンダー", systemImage: "calendar") }
                .tag(AppTab.calendar)

            RecordView()
                .tabItem { Label("記録", systemImage: "dumbbell.fill") }
                .tag(AppTab.workout)

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
        // 通知タップのルーティング（type に応じて該当タブへ）。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeOpenDestination)) { note in
            switch note.userInfo?["type"] as? String {
            case "reaction", "friend_checkin": selection = .social
            case "workout": selection = .workout
            case "analytics": selection = .analytics
            case "recap", "checkin": selection = .calendar
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
