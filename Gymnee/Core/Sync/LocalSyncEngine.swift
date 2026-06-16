import Foundation
import Observation

/// ローカルのみの同期エンジン（§3）。outbox に変更を積み、ファイルへ永続化する。
/// 送出は行わない（Supabase 接続時に push()/pull() の中身を実装すればよい形で隔離）。
@MainActor
@Observable
final class LocalSyncEngine: SyncEngine {
    private(set) var outbox: [PendingChange]
    private let url: URL

    init(persistenceURL: URL? = nil) {
        let resolved = persistenceURL ?? OutboxStore.defaultURL()
        self.url = resolved
        self.outbox = OutboxStore.load(from: resolved)
    }

    var pendingCount: Int { outbox.count }

    func enqueue(_ change: PendingChange) {
        // 同一レコードの既存待ちは最新の 1 件に畳む（LWW、§9-7）。
        outbox.removeAll { $0.recordId == change.recordId && $0.entity == change.entity }
        outbox.append(change)
        persist()
    }

    func push() async throws {
        // v0: バックエンド未接続のため no-op。実接続時はここで Supabase へ upsert/delete し、
        // 成功した変更を outbox から除去して persist() する。
    }

    func pull() async throws {
        // v0: no-op。実接続時にリモート差分を取得し ConflictResolver で統合。
    }

    private func persist() {
        OutboxStore.save(outbox, to: url)
    }
}
