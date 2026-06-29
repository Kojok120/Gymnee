import Foundation

/// pull のフル取得時に「ローカルに残った余剰行」を判定する純粋ロジック。
/// 他端末での DELETE（いいね取消／コメント削除）は差分 pull に tombstone が無く届かないため、
/// サーバー全件 id を正として、未送出でない（isDirty=false の）ローカル行のうち
/// サーバーに存在しないものを削除対象とする。未送出（自分が作成しまだ push していない）行は守る。
enum SyncReconciler {
    /// 削除すべきローカル行の id。`local` は (id, isDirty) の射影、`serverIds` はサーバー全件 id。
    static func orphanIds(local: [(id: UUID, isDirty: Bool)], serverIds: Set<UUID>) -> [UUID] {
        local.filter { !$0.isDirty && !serverIds.contains($0.id) }.map(\.id)
    }
}
