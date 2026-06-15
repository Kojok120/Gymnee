import SwiftUI

enum AppTab: Hashable {
    case calendar, workout, checkin, social, shop
}

/// アプリのルート。未ログインは Onboarding、ログイン済みはタブ骨格を表示する（§5）。
/// 中央の「チェックイン」タブは選択時にフルスクリーンのチェックインフローを起動する（§6.3）。
struct RootView: View {
    @Environment(AuthService.self) private var auth
    @State private var selection: AppTab = .calendar
    @State private var showCheckIn = false

    var body: some View {
        Group {
            if auth.isSignedIn {
                mainTabs
            } else {
                OnboardingView()
            }
        }
        .animation(.default, value: auth.isSignedIn)
    }

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
