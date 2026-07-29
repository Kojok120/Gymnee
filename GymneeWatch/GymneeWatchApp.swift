import SwiftUI

/// watchOS アプリ（§6.10）。手首から連続記録・今週の達成・次の予定を確認する。
@main
struct GymneeWatchApp: App {
    init() {
        // 本体との WCSession を起動（スナップショット受信の土台）。
        WatchConnector.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
    }
}
