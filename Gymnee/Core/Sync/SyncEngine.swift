import Foundation

/// 同期操作種別。
enum SyncOperation: String, Codable, Sendable {
    case upsert
    case delete
}

/// 送出待ちの変更（outbox の 1 件）。
struct PendingChange: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var entity: String
    var recordId: UUID
    var operation: SyncOperation
    var updatedAt: Date

    init(id: UUID = UUID(), entity: String, recordId: UUID, operation: SyncOperation, updatedAt: Date) {
        self.id = id
        self.entity = entity
        self.recordId = recordId
        self.operation = operation
        self.updatedAt = updatedAt
    }
}

/// 同期コンフリクト方針（§9-7）。
/// 既定は last-write-wins（updatedAt 比較）。`exercise_sets` は追記型のため衝突しない設計。
enum ConflictResolver {
    enum Winner: Equatable, Sendable { case local, remote }

    /// updatedAt が新しい側を採用。同時刻はローカル優先（オフラインファースト＝ローカルが正、§3）。
    static func resolve(localUpdatedAt: Date, remoteUpdatedAt: Date) -> Winner {
        if localUpdatedAt >= remoteUpdatedAt {
            return .local
        } else {
            return .remote
        }
    }
}
