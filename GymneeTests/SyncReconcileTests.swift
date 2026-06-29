import XCTest
@testable import Gymnee

/// 他端末での DELETE（いいね取消／コメント削除）を伝播する reconcile の判定ロジックのテスト。
/// 差分 pull では届かないサーバー削除を、フル取得した id 集合との差分照合で反映する。
final class SyncReconcileTests: XCTestCase {

    func testOrphanIdsDeletesServerRemovedButKeepsUnsynced() {
        let kept = UUID()          // サーバーに残る（pull 済み・isDirty=false）
        let removed = UUID()       // サーバーで取消（pull 済み・isDirty=false・serverIds に無い）
        let mineUnsynced = UUID()  // 自分が付けて未送出（isDirty=true）→ 守る

        let local = [(id: kept, isDirty: false), (id: removed, isDirty: false), (id: mineUnsynced, isDirty: true)]
        let orphans = SyncReconciler.orphanIds(local: local, serverIds: [kept])

        XCTAssertEqual(orphans, [removed])
    }

    func testOrphanIdsEmptyServerWipesOnlySynced() {
        let synced = UUID()
        let unsynced = UUID()
        let local = [(id: synced, isDirty: false), (id: unsynced, isDirty: true)]

        // サーバーが空（全削除）→ 同期済みだけ削除対象、未送出は守る。
        XCTAssertEqual(SyncReconciler.orphanIds(local: local, serverIds: []), [synced])
    }

    func testOrphanIdsNoneWhenAllPresent() {
        let a = UUID(); let b = UUID()
        let local = [(id: a, isDirty: false), (id: b, isDirty: false)]
        XCTAssertTrue(SyncReconciler.orphanIds(local: local, serverIds: [a, b]).isEmpty)
    }
}
