import XCTest
@testable import Gymnee

/// 同期コンフリクト方針（§9-7 last-write-wins）のテスト。
final class ConflictResolverTests: XCTestCase {

    func testLocalWinsWhenNewer() {
        let now = Date(timeIntervalSince1970: 1_000)
        let older = Date(timeIntervalSince1970: 500)
        XCTAssertEqual(ConflictResolver.resolve(localUpdatedAt: now, remoteUpdatedAt: older), .local)
    }

    func testRemoteWinsWhenNewer() {
        let now = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(ConflictResolver.resolve(localUpdatedAt: now, remoteUpdatedAt: newer), .remote)
    }

    func testLocalWinsOnTie() {
        // 同時刻はローカル優先（オフラインファースト＝ローカルが正、§3）。
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(ConflictResolver.resolve(localUpdatedAt: t, remoteUpdatedAt: t), .local)
    }

    func testExerciseSetsAreAppendOnly() {
        XCTAssertTrue(ConflictResolver.isAppendOnly(entity: "exercise_sets"))
        XCTAssertFalse(ConflictResolver.isAppendOnly(entity: "workouts"))
    }
}

/// outbox の畳み込み（同一レコードは最新 1 件）・永続化のテスト。
@MainActor
final class LocalSyncEngineTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID().uuidString).json")
    }

    func testEnqueueCoalescesSameRecord() {
        let engine = LocalSyncEngine(persistenceURL: tempURL())
        let recordId = UUID()
        engine.enqueue(PendingChange(entity: "visits", recordId: recordId, operation: .upsert, updatedAt: Date(timeIntervalSince1970: 1)))
        engine.enqueue(PendingChange(entity: "visits", recordId: recordId, operation: .upsert, updatedAt: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(engine.pendingCount, 1)
        XCTAssertEqual(engine.outbox.first?.updatedAt, Date(timeIntervalSince1970: 2))
    }

    func testEnqueueKeepsDistinctRecords() {
        let engine = LocalSyncEngine(persistenceURL: tempURL())
        engine.enqueue(PendingChange(entity: "visits", recordId: UUID(), operation: .upsert, updatedAt: .now))
        engine.enqueue(PendingChange(entity: "workouts", recordId: UUID(), operation: .upsert, updatedAt: .now))
        XCTAssertEqual(engine.pendingCount, 2)
    }

    func testOutboxPersistsAcrossInstances() {
        let url = tempURL()
        let recordId = UUID()
        let first = LocalSyncEngine(persistenceURL: url)
        first.enqueue(PendingChange(entity: "visits", recordId: recordId, operation: .upsert, updatedAt: Date(timeIntervalSince1970: 5)))
        // 別インスタンス（＝再起動相当）で復元される。
        let second = LocalSyncEngine(persistenceURL: url)
        XCTAssertEqual(second.pendingCount, 1)
        XCTAssertEqual(second.outbox.first?.recordId, recordId)
        try? FileManager.default.removeItem(at: url)
    }
}
