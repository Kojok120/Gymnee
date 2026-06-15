import SwiftUI

/// watchOS アプリ（§6.10）。手首からのクイックチェックイン・セッション概要。
@main
struct GymneeWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
    }
}
