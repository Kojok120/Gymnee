import SwiftUI

/// watchOS アプリ（§6.10）。手首からのクイックチェックイン・セッション概要。
@main
struct GymneeWatchApp: App {
    init() {
        // 本体との WCSession を起動（クイックチェックイン送信・スナップショット受信の土台）。
        WatchConnector.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
    }
}
