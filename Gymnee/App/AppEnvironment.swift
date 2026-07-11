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
    let subscription: SubscriptionService
    let calendar: CalendarService
    let googleCalendar: GoogleCalendarService

    init(container: ModelContainer? = nil) {
        let resolved = container ?? GymneeSchema.makeContainer()
        self.container = resolved
        self.sync = LocalSyncEngine()
        self.auth = AuthService()
        self.location = LocationService()
        self.health = HealthKitService()
        self.notifications = NotificationService()
        self.errors = AppErrorCenter()
        self.subscription = SubscriptionService()
        self.calendar = CalendarService()
        self.googleCalendar = GoogleCalendarService()
        self.googleCalendar.restore()
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
        pushDirtyOwnProfileIfNeeded()
        // APNs トークン取得時に Supabase の device_tokens へ登録（要サインイン＝best-effort）。
        PushTokenCenter.shared.onToken = { token in
            Task { try? await client.registerDeviceToken(token) }
        }
        // データ通知を受けたら最新差分を取り込む（実配信は APNs 鍵が前提＝best-effort）。
        PushTokenCenter.shared.onRemoteNotification = { [weak self] _ in
            guard let self else { return }
            Task { await self.sync.syncNow(force: true) }
        }
        // バックエンドサインイン成功時：旧ローカルデータを新 userId へ付け替え→同期。
        // oldUserId は AuthService が IdentityAdoptionPolicy で選別済み（ゲスト/匿名期間の
        // 引き継ぎのみ非 nil。恒久アカウント切替では nil＝付け替えなし）。
        auth.onBackendSignIn = { [weak self] oldUserId, newUserId in
            guard let self else { return }
            if let oldUserId, oldUserId != newUserId {
                LocalDataMigrator.reassign(from: oldUserId, to: newUserId, context: self.container.mainContext, sync: self.sync)
            }
            // サインイン（特に後発サインイン/アカウント切替）時に、取得済み APNs トークンを
            // 現在のユーザーへ紐付け直す。これが無いと device_tokens が旧/別ユーザーに残り push が不達。
            if let token = PushTokenCenter.shared.apnsToken {
                Task { try? await client.registerDeviceToken(token) }
            }
            Task { await self.sync.syncNow(force: true) }
        }
    }

    /// ユーザー作成種目はローカル生成時点では outbox に積まれないことがあり、
    /// routine_exercises/workout_exercises が参照する exercise_id がサーバーに無く
    /// FK 違反（23503）になる。起動時に一度だけカスタム種目を upsert で積み、
    /// 依存行より先に送られるようにする（押し順は exercises → *_exercises）。
    /// プリセット（is_custom=false）はサーバーマスタ（created_by IS NULL・migration 0030）が正で
    /// push しない。旧実装は全プリセットを created_by=自分 で push しており、2人目以降の
    /// 同 id upsert が RLS(42501) で outbox に永久滞留するバグの原因だった。
    private func backfillExercisesIfNeeded() {
        let key = "gymnee.exerciseSyncBackfill.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let exercises = (try? container.mainContext.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isCustom == true })
        )) ?? []
        if !exercises.isEmpty {
            sync.enqueueBatch(exercises.map {
                PendingChange(entity: "exercises", recordId: $0.id, operation: .upsert, updatedAt: .now)
            })
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// 未送出（isDirty）の自分の Profile を起動時に outbox へ積む（自己修復）。
    /// updateDisplayName は「同期は呼び出し側で enqueue」の契約だが、初期設定
    /// （SetupOnboardingView）が enqueue しておらず、表示名の変更がサーバへ届かないまま
    /// フレンド側で「ゲスト」表示になる不具合があった。過去に取りこぼした変更もここで送る。
    private func pushDirtyOwnProfileIfNeeded() {
        guard let uid = auth.currentUserId else { return }
        let descriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.id == uid && $0.isDirty })
        guard let profile = (try? container.mainContext.fetch(descriptor))?.first else { return }
        sync.enqueue(PendingChange(entity: "profiles", recordId: profile.id, operation: .upsert, updatedAt: profile.updatedAt))
    }

    /// 再起動後にバックエンドセッションを復元する（GymneeApp の起動 task から呼ぶ）。
    func bootstrapBackend() async {
        await auth.restoreBackendSession()
    }
}
