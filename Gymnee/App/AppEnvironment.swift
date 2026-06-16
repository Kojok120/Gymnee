import Foundation
import SwiftData
import Observation

/// アプリ全体の DI コンテナ（§ アーキテクチャ方針）。
/// 各サービスをここに集約し `.environment(...)` で View ツリーへ注入する。
@MainActor
@Observable
final class AppEnvironment {
    let container: ModelContainer
    let auth: AuthService
    let sync: LocalSyncEngine
    let location: LocationService
    let health: HealthKitService
    let notifications: NotificationService
    let errors: AppErrorCenter

    init(container: ModelContainer? = nil) {
        let resolved = container ?? GymneeSchema.makeContainer()
        self.container = resolved
        self.sync = LocalSyncEngine()
        self.auth = AuthService()
        self.location = LocationService()
        self.health = HealthKitService()
        self.notifications = NotificationService()
        self.errors = AppErrorCenter()
        self.auth.bootstrap(context: resolved.mainContext)
        self.notifications.configure()
    }
}
