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
        // Apple Watch との WCSession を起動（手首からのチェックイン受信・スナップショット配布）。
        WatchConnector.shared.activate()
        configureRemoteSyncIfAvailable()
    }

    /// `Supabase.plist` があればリモート同期を有効化する。無ければローカルのみで継続（オフラインファースト）。
    private func configureRemoteSyncIfAvailable() {
        guard let config = SupabaseConfig.load() else { return }
        let client = SupabaseClient(config: config)
        sync.configureRemote(client)
        sync.store = SwiftDataSyncStore(context: container.mainContext)
        auth.configureSupabase(client)
        backfillExercisesIfNeeded()
        // APNs トークン取得時に Supabase の device_tokens へ登録（要サインイン＝best-effort）。
        PushTokenCenter.shared.onToken = { token in
            Task { try? await client.registerDeviceToken(token) }
        }
        // データ通知を受けたら最新差分を取り込む（実配信は APNs 鍵が前提＝best-effort）。
        PushTokenCenter.shared.onRemoteNotification = { [weak self] _ in
            guard let self else { return }
            Task { await self.sync.syncNow() }
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

    /// プリセット種目はローカル seed（isDirty=false）でアウトボックスに積まれず、サーバーに
    /// 送られない。そのため routine_exercises/workout_exercises が参照する exercise_id が
    /// サーバーに無く FK 違反（23503）になる。起動時に一度だけ全種目を upsert で積み、
    /// 依存行より先に送られるようにする（押し順は exercises → *_exercises）。
    private func backfillExercisesIfNeeded() {
        let key = "gymnee.exerciseSyncBackfill.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let exercises = (try? container.mainContext.fetch(FetchDescriptor<Exercise>())) ?? []
        guard !exercises.isEmpty else { return }
        sync.enqueueBatch(exercises.map {
            PendingChange(entity: "exercises", recordId: $0.id, operation: .upsert, updatedAt: .now)
        })
        UserDefaults.standard.set(true, forKey: key)
    }

    /// 再起動後にバックエンドセッションを復元する（GymneeApp の起動 task から呼ぶ）。
    func bootstrapBackend() async {
        await auth.restoreBackendSession()
    }
}
