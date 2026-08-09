import XCTest
import SwiftData
@testable import Gymnee

/// 遠征記録の永続化と状態遷移のテスト。
/// スキーマ v2（`ExpeditionRun` 追加）が実際にコンテナへ載ることの確認も兼ねる。
final class ExpeditionRunStoreTests: XCTestCase {

    private let userId = UUID()
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: GymneeSchema.schema,
            configurations: ModelConfiguration(schema: GymneeSchema.schema, isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeRun(finishesIn seconds: TimeInterval, in context: ModelContext) -> ExpeditionRun {
        let run = ExpeditionRun(
            userId: userId,
            courseId: "iron-forest",
            startedAt: base,
            finishesAt: base.addingTimeInterval(seconds),
            energySpent: 45
        )
        context.insert(run)
        return run
    }

    func testExpeditionRunIsPersistedInSchemaV2() throws {
        let context = try makeContext()
        _ = makeRun(finishesIn: 3_600, in: context)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<ExpeditionRun>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.courseId, "iron-forest")
        XCTAssertEqual(stored.first?.energySpent, 45)
    }

    func testStateMachineFromInProgressToClaimed() throws {
        let context = try makeContext()
        let run = makeRun(finishesIn: 3_600, in: context)

        // 出発直後: 進行中。
        XCTAssertTrue(run.isInProgress(asOf: base))
        XCTAssertFalse(run.isAwaitingClaim(asOf: base))
        XCTAssertFalse(run.isClaimed)

        // 帰還後・未受取: 受け取り待ち。
        let afterReturn = base.addingTimeInterval(3_601)
        XCTAssertFalse(run.isInProgress(asOf: afterReturn))
        XCTAssertTrue(run.isAwaitingClaim(asOf: afterReturn))

        // 受け取り後: どちらでもなくなる。
        let item = Expedition.reward(courseId: run.courseId, seed: run.id)
        run.rewardItemId = item.id
        run.claimedAt = afterReturn
        try context.save()

        XCTAssertTrue(run.isClaimed)
        XCTAssertFalse(run.isAwaitingClaim(asOf: afterReturn))
        XCTAssertEqual(run.reward, item, "受け取った装備がカタログから引き直せる")
    }

    func testCourseLookupFromRun() throws {
        let context = try makeContext()
        let run = makeRun(finishesIn: 60, in: context)
        XCTAssertEqual(run.course?.id, "iron-forest")
    }

    /// 手持ちの元気は「獲得 − 遠征に払った分」。遠征を出すと確かに減る。
    func testSpendingReducesAvailableEnergy() throws {
        let sessions = [
            CharacterProgress.SessionInput(completedAt: base, completedSets: 12, volumeKg: 3_000),
            CharacterProgress.SessionInput(completedAt: base, completedSets: 12, volumeKg: 3_000),
        ]
        let before = Expedition.availableEnergy(sessions: sessions, spent: 0)
        let after = Expedition.availableEnergy(sessions: sessions, spent: 45)
        XCTAssertEqual(before - after, 45)
    }
}
