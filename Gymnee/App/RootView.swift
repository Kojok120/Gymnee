import SwiftUI

enum AppTab: Hashable {
    case calendar, workout, checkin, social, shop
}

/// アプリのルート。未ログインは Onboarding、ログイン済みはタブ骨格を表示する（§5）。
/// 中央の「チェックイン」タブは選択時にフルスクリーンのチェックインフローを起動する（§6.3）。
struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppErrorCenter.self) private var errors
    @Environment(\.modelContext) private var context
    @State private var selection: AppTab = .calendar
    @State private var showCheckIn = false
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
        }
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private func debugScreen(_ name: String, userId: UUID) -> some View {
        switch name {
        case "gym": NavigationStack { GymListView(userId: userId) }
        case "addgym": AddGymView(userId: userId)
        case "checkin": CheckInView()
        case "profile": NavigationStack { ProfileView(userId: userId) }
        case "social": SocialFeedView()
        case "friends": SocialFeedView(initialTab: 1)
        case "shop": ShopView()
        case "routine":
            if let r = debugRoutine {
                NavigationStack { RoutineEditorView(routine: r) }
            } else {
                NavigationStack { RoutinesView(userId: userId) }
            }
        case "analytics": NavigationStack { AnalyticsView(userId: userId) }
        case "body": NavigationStack { BodyMetricsView(userId: userId) }
        case "photos": NavigationStack { ProgressPhotosView(userId: userId) }
        case "share":
            ShareCardEditorView(content: ShareCardContent(
                image: nil, gymName: "Gymnee 渋谷", streak: 3,
                prText: "ベンチ 80kg", exerciseSummary: "胸・三頭 3種目"
            ))
        case "workout": WorkoutHomeView()
        case "logger":
            if let w = debugWorkout {
                NavigationStack { WorkoutLoggerView(workout: w) }
            } else {
                WorkoutHomeView()
            }
        default: mainTabs
        }
    }
    #endif

    private var mainTabs: some View {
        TabView(selection: tabBinding) {
            CalendarHomeView()
                .tabItem { Label("カレンダー", systemImage: "calendar") }
                .tag(AppTab.calendar)

            WorkoutHomeView()
                .tabItem { Label("記録", systemImage: "dumbbell.fill") }
                .tag(AppTab.workout)

            Color.clear
                .tabItem { Label("チェックイン", systemImage: "camera.fill") }
                .tag(AppTab.checkin)

            SocialFeedView()
                .tabItem { Label("ソーシャル", systemImage: "person.2.fill") }
                .tag(AppTab.social)

            ShopView()
                .tabItem { Label("ショップ", systemImage: "bag.fill") }
                .tag(AppTab.shop)
        }
        .tint(Theme.energy)
        .fullScreenCover(isPresented: $showCheckIn) {
            CheckInView()
        }
    }

    /// 中央タブ選択をチェックインフロー起動に振り替えるバインディング。
    private var tabBinding: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == .checkin {
                    showCheckIn = true
                } else {
                    selection = newValue
                }
            }
        )
    }
}
