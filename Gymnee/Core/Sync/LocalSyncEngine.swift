import Foundation
import Observation

/// ローカル優先の同期エンジン（§3）。outbox に変更を積みファイルへ永続化する。
///
/// **リモート未設定時はローカルのみ**（push/pull は no-op）でオフラインファーストを維持する。
/// `Supabase.plist` が存在し `configureRemote(_:)` が呼ばれると、push() で outbox を Supabase へ送出し、
/// pull() でリモート差分を取り込む。SwiftData 行 ⇄ JSON の変換は `SyncBackingStore` 実装に委ねる
/// （アプリ層が SwiftData にアクセスして担う＝この層は永続化方式に非依存）。
@MainActor
@Observable
final class LocalSyncEngine: SyncEngine {
    private(set) var outbox: [PendingChange]
    private let url: URL

    /// 同期状態の可視化（Settings 表示・デバッグ用）。
    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?
    @ObservationIgnored private var autoSyncTask: Task<Void, Never>?

    /// リモート（未設定ならローカルのみ）。
    @ObservationIgnored private var remote: SupabaseClient?
    /// SwiftData 行の符号化／復号を担うアプリ層の実装。
    /// strong 保持（SwiftDataSyncStore は ModelContext のみ参照し循環しない）。weak だと即解放され同期が無言で no-op になる。
    @ObservationIgnored var store: (any SyncBackingStore)?

    /// 同期対象テーブル（pull の対象。push は outbox の entity を使う）。
    @ObservationIgnored
    private let syncedTables = [
        "profiles", "gyms", "gym_equipment", "visits", "visit_partners",
        "workouts", "exercises", "workout_exercises", "exercise_sets",
        "routines", "routine_exercises", "personal_records",
        "body_metrics", "progress_photos", "follows", "blocks", "reports", "feed_items", "post_reactions",
        "comments", "products", "supply_logs", "subscriptions",
    ]

    init(persistenceURL: URL? = nil) {
        let resolved = persistenceURL ?? OutboxStore.defaultURL()
        self.url = resolved
        self.outbox = OutboxStore.load(from: resolved)
    }

    /// リモートを差し込む（Supabase 接続時に AppEnvironment から呼ぶ）。
    func configureRemote(_ client: SupabaseClient?) {
        self.remote = client
    }

    var isRemoteEnabled: Bool { remote != nil }
    /// 多重起動を避けるためのフラグ。
    @ObservationIgnored private var isSyncing = false

    /// 同期を 1 サイクル実行（pull→push）。サインイン時・アプリ復帰時などに呼ぶ。
    /// リモート未設定なら何もしない（ローカルのみ）。
    /// 同期クールダウン。前景化やフィード再表示の連発で 21 テーブルのフルpullが乱発するのを防ぐ。
    /// 明示同期（サインイン直後・手動「今すぐ同期」・プロフィール保存）は force:true で即時実行。
    @ObservationIgnored private let syncCooldown: TimeInterval = 30

    func syncNow(force: Bool = false) async {
        guard isRemoteEnabled, !isSyncing else { return }
        if !force, let last = lastSyncedAt, Date().timeIntervalSince(last) < syncCooldown { return }
        isSyncing = true
        defer { isSyncing = false }
        try? await pull()   // 先にリモート差分を取り込み（商品カタログ等）
        try? await push()   // ローカルの未送出を送る
    }
    var pendingCount: Int { outbox.count }

    /// outbox 重複判定キー（entity + recordId の組）。
    private struct PendingKey: Hashable {
        let entity: String
        let recordId: UUID
        init(_ c: PendingChange) { entity = c.entity; recordId = c.recordId }
    }

    func enqueue(_ change: PendingChange) {
        // 同一レコードの既存待ちは最新の 1 件に畳む（LWW、§9-7）。
        outbox.removeAll { $0.recordId == change.recordId && $0.entity == change.entity }
        outbox.append(change)
        persist()
        scheduleAutoSync()
    }

    /// 複数変更をまとめて積む（ディスク書込・自動同期は 1 回だけ）。
    /// 移行や投稿一括発行のような大量 enqueue でメインスレッドが詰まらないようにするため。
    func enqueueBatch(_ changes: [PendingChange]) {
        guard !changes.isEmpty else { return }
        // 同一レコード(entity+recordId)は最新 1 件へ畳む（LWW、§9-7）。
        // 既存 outbox と追加分をキー索引で突き合わせ、要素ごとの全走査 removeAll（O(n*m)）を避ける。
        var indexByKey: [PendingKey: Int] = [:]
        for (i, c) in outbox.enumerated() { indexByKey[PendingKey(c)] = i }
        for change in changes {
            let key = PendingKey(change)
            if let i = indexByKey[key] {
                outbox[i] = change
            } else {
                indexByKey[key] = outbox.count
                outbox.append(change)
            }
        }
        persist()
        scheduleAutoSync()
    }

    /// データ変更後に少し待ってから自動「送信」する（連続入力をまとめる debounce）。
    /// pull（19テーブルの取得）は走らせず push だけ＝軽量。これが無いとチェックイン直後の変更が送られない。
    func scheduleAutoSync(after seconds: Double = 1.5) {
        guard isRemoteEnabled else { return }
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.pushOnly()
        }
    }

    /// 送信のみ（pull しない）。データ変更直後の軽量同期に使う。
    func pushOnly() async {
        guard isRemoteEnabled, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        try? await push()
    }

    /// 指定ユーザーのプロフィールを id 指定で取得し、ローカルへ反映する。
    /// 差分 pull が取り込めないフォロー相手/フィード著者のプロフィール（名前・アバター）を確実に揃える。
    func ensureProfiles(ids: Set<UUID>) async {
        guard let remote, let store, !ids.isEmpty else { return }
        do {
            let rows = try await remote.fetchProfiles(ids: Array(ids))
            if !rows.isEmpty { store.apply(table: "profiles", rows: rows) }
        } catch {
            // 取得失敗はフィード表示の致命ではないため握りつぶす（次回再試行）。
        }
    }

    /// ローカルの変更を Supabase へ送出する。成功分を outbox から除去する。
    func push() async throws {
        guard let remote, let store else { return } // リモート未設定＝no-op（ローカルのみ）

        // FK 親依存（visits→gyms 等）を補完。未enqueue/詰まりの親も先に送れ、既存の詰まりを自己修復する。
        var snapshot = outbox
        var present = Set(outbox.map { PendingKey($0) })
        for change in outbox {
            for dep in store.dependencies(for: change) where present.insert(PendingKey(dep)).inserted {
                snapshot.append(dep)
            }
        }

        var succeeded: [UUID] = []  // PendingChange.id
        var lastErr: String?

        // FK 依存順（親→子）で処理する。Dictionary の反復順は不定で、visits が gyms より先に
        // 送られると FK 違反(23503)になるため、syncedTables の依存順を明示的に使う。
        let byEntity = Dictionary(grouping: snapshot, by: { $0.entity })
        let orderedTables = syncedTables + byEntity.keys.filter { !syncedTables.contains($0) }
        for table in orderedTables {
            guard let changes = byEntity[table] else { continue }
            // 削除
            let deletes = changes.filter { $0.operation == .delete }
            if !deletes.isEmpty {
                do {
                    try await remote.delete(table: table, ids: deletes.map { $0.recordId })
                    succeeded.append(contentsOf: deletes.map { $0.id })
                } catch { lastErr = error.localizedDescription }
            }

            // upsert：payload を 1 回だけ計算して仕分け。作れない（対象が消えた等）は成功扱いで除去。
            var encodableChanges: [PendingChange] = []
            var encodableRows: [[String: Any]] = []
            for change in changes where change.operation == .upsert {
                if let payload = store.payload(for: change) {
                    encodableChanges.append(change)
                    encodableRows.append(payload)
                } else {
                    succeeded.append(change.id)
                }
            }
            guard !encodableRows.isEmpty else { continue }

            // まずバッチ送信。失敗したら 1 件ずつ送り、通る行だけ通す
            // （古い/不正な 1 行に新しい正しい行が巻き添えにならないように）。
            do {
                try await remote.upsert(table: table, rows: encodableRows)
                succeeded.append(contentsOf: encodableChanges.map { $0.id })
            } catch {
                lastErr = error.localizedDescription
                for (index, change) in encodableChanges.enumerated() {
                    do {
                        try await remote.upsert(table: table, rows: [encodableRows[index]])
                        succeeded.append(change.id)
                    } catch { lastErr = error.localizedDescription }
                }
            }
        }

        outbox.removeAll { succeeded.contains($0.id) }
        persist()
        lastSyncedAt = .now
        lastError = lastErr
    }

    /// リモート差分を取り込み、ConflictResolver でローカルへ統合する。
    func pull() async throws {
        guard let remote, let store else { return } // リモート未設定＝no-op

        // テーブル間に取り込み順依存は無い（衝突解決は ConflictResolver で行単位）。各テーブルの
        // ネットワーク取得を並列化し、直列だと 19 テーブル分積み上がる往復レイテンシを解消する。
        // select は actor 上で並行実行され、apply/setLastPulledAt は @MainActor の子タスクで順次反映する。
        let targets = syncedTables.map { (table: $0, since: store.lastPulledAt(table: $0)) }
        await withTaskGroup(of: Void.self) { group in
            for target in targets {
                group.addTask { @MainActor in
                    // 個別テーブル失敗は握りつぶし、他テーブルを継続（best-effort 差分 pull）。
                    guard let rows = try? await remote.select(table: target.table, updatedSince: target.since),
                          !rows.isEmpty else { return }
                    store.apply(table: target.table, rows: rows)
                    // 取得行の最大 updated_at を次回基準にする。
                    if let newest = Self.newestUpdatedAt(in: rows) {
                        store.setLastPulledAt(newest, table: target.table)
                    }
                }
            }
        }
    }

    private func persist() {
        OutboxStore.save(outbox, to: url)
    }

    /// リモート行群から最新の updated_at を取り出す（pull 基準の更新用）。
    private static func newestUpdatedAt(in rows: [[String: Any]]) -> Date? {
        var newest: Date?
        for row in rows {
            guard let s = row["updated_at"] as? String,
                  let date = ISO8601DateFormatter.supabase.date(from: s) else { continue }
            if let current = newest {
                if date > current { newest = date }
            } else {
                newest = date
            }
        }
        return newest
    }
}

/// SwiftData 行 ⇄ Supabase JSON の変換境界（アプリ層が実装）。
/// 同期エンジンを SwiftData 非依存に保つための seam。
///
/// **TODO（M2 実接続）**: 19 テーブル分の符号化／復号を実装する。
///   - `payload(for:)`: recordId からモデルを引き、snake_case の列 JSON（外部キー含む）に変換。
///   - `apply(table:rows:)`: 受信行を upsert。`ConflictResolver.resolve` で updated_at 比較し新しい側を採用。
@MainActor
protocol SyncBackingStore: AnyObject {
    /// outbox の 1 件を送信用の行 JSON に変換する（削除済み／対象外は nil）。
    func payload(for change: PendingChange) -> [String: Any]?
    /// pull で取得したリモート行をローカルへ適用する。
    func apply(table: String, rows: [[String: Any]])
    /// 当該テーブルの最終 pull 時刻（差分取得の基準。未取得なら nil）。
    func lastPulledAt(table: String) -> Date?
    /// 最終 pull 時刻を更新する。
    func setLastPulledAt(_ date: Date, table: String)
    /// FK 親依存（例: visits→gyms）。push 時にこれらを先に送って外部キー違反(23503)を防ぐ。既定は依存なし。
    func dependencies(for change: PendingChange) -> [PendingChange]
}

extension SyncBackingStore {
    func dependencies(for change: PendingChange) -> [PendingChange] { [] }
}
