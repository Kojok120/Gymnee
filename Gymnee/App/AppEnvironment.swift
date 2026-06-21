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
        configureRemoteSyncIfAvailable()
    }

    /// `Supabase.plist` があればリモート同期を有効化する。無ければローカルのみで継続（オフラインファースト）。
    private func configureRemoteSyncIfAvailable() {
        guard let config = SupabaseConfig.load() else { return }
        let client = SupabaseClient(config: config)
        sync.configureRemote(client)
        sync.store = SwiftDataSyncStore(context: container.mainContext)
        auth.configureSupabase(client)
        // APNs トークン取得時に Supabase の device_tokens へ登録（要サインイン＝best-effort）。
        PushTokenCenter.shared.onToken = { token in
            Task { try? await client.registerDeviceToken(token) }
        }
        // バックエンドサインイン成功時：旧ローカルデータを新 userId へ付け替え→同期。
        auth.onBackendSignIn = { [weak self] oldUserId, newUserId in
            guard let self else { return }
            if let oldUserId, oldUserId != newUserId {
                LocalDataMigrator.reassign(from: oldUserId, to: newUserId, context: self.container.mainContext, sync: self.sync)
            }
            Task { await self.sync.syncNow() }
        }
    }

    /// 再起動後にバックエンドセッションを復元する（GymneeApp の起動 task から呼ぶ）。
    func bootstrapBackend() async {
        await auth.restoreBackendSession()
    }
}
