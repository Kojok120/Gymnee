import Foundation
import Observation

/// ローカルのみの同期エンジン（§3）。outbox に変更を積むだけで送出はしない。
/// Supabase 接続時に push()/pull() の中身を実装すればよい形で隔離している。
@MainActor
@Observable
final class LocalSyncEngine: SyncEngine {
    private(set) var outbox: [PendingChange] = []

    init() {}

    var pendingCount: Int { outbox.count }

    func enqueue(_ change: PendingChange) {
        // 同一レコードの既存待ちは最新の 1 件に畳む（LWW、§9-7）。
        outbox.removeAll { $0.recordId == change.recordId && $0.entity == change.entity }
        outbox.append(change)
    }

    func push() async throws {
        // v0: バックエンド未接続のため no-op。実接続時にここで Supabase へ upsert/delete。
    }

    func pull() async throws {
        // v0: no-op。実接続時にここでリモート差分を取得し ConflictResolver で統合。
    }
}
