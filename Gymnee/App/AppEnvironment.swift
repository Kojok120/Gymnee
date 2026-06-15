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

    init(container: ModelContainer? = nil) {
        let resolved = container ?? GymneeSchema.makeContainer()
        self.container = resolved
        self.sync = LocalSyncEngine()
        self.auth = AuthService()
        self.auth.bootstrap(context: resolved.mainContext)
    }
}
