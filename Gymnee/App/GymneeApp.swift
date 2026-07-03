import SwiftUI
import SwiftData

@main
struct GymneeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var env = AppEnvironment()

    init() { AppAppearance.configure() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.lime)
                .environment(env)
                .environment(env.auth)
                .environment(env.sync)
                .environment(env.location)
                .environment(env.health)
                .environment(env.notifications)
                .environment(env.errors)
                .environment(env.subscription)
                .environment(env.calendar)
                .environment(env.googleCalendar)
                .modelContainer(env.container)
                // Google サインインの OAuth コールバック（reversed client id スキーム）と
                // フレンド招待の Universal Link（https://gymnee.app/invite/?u=...）を処理。
                .onOpenURL { url in
                    if env.googleCalendar.handleURL(url) { return }
                    guard let inviter = InviteLink.userId(from: url) else { return }
                    // 未サインインでも後で拾えるよう保留し、ソーシャルタブへの遷移を要求する。
                    UserDefaults.standard.set(inviter.uuidString, forKey: InviteLink.pendingDefaultsKey)
                    NotificationCenter.default.post(
                        name: .gymneeOpenDestination, object: nil, userInfo: ["type": "invite"]
                    )
                }
                // 起動時にバックエンドセッションを復元（トークン更新）→ その後の同期が認証付きで通る。
                .task { await env.bootstrapBackend() }
                // Premium 商品取得＋権限同期。
                .task { await env.subscription.bootstrap() }
                // アプリ復帰時に同期（リモート未設定なら no-op）。
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await env.sync.syncNow() } }
                }
                // サインイン完了時に同期（Apple サインインでトークンが入った直後）。
                .onChange(of: env.auth.isSignedIn) { _, signedIn in
                    if signedIn { Task { await env.sync.syncNow(force: true) } }
                }
        }
    }
}

/// UIKit 由来の chrome（タブバー/ナビバー）の見た目を設計言語に合わせる。
/// SwiftUI だけでは届かない範囲をここで一括設定する。
enum AppAppearance {
    static func configure() {
        // タブバー: 半透明マテリアル + lime の選択色。
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        let lime = UIColor(Theme.lime)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.selected.iconColor = lime
            item.selected.titleTextAttributes = [.foregroundColor: lime]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // ナビバー: ラージタイトルを丸ゴシック寄りの太字に。
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        let rounded = UIFont.systemFont(ofSize: 34, weight: .bold)
        let descriptor = rounded.fontDescriptor.withDesign(.rounded) ?? rounded.fontDescriptor
        nav.largeTitleTextAttributes = [.font: UIFont(descriptor: descriptor, size: 34)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }
}
