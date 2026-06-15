import SwiftUI
import SwiftData

@main
struct GymneeApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(env.auth)
                .environment(env.sync)
                .modelContainer(env.container)
        }
    }
}
