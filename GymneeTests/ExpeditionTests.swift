import XCTest
@testable import Gymnee

/// 遠征（元気・コース・報酬抽選）のテスト。
/// 「燃料は現実のトレーニングだけ」「抽選は決定的」の 2 点が守られているかを見る。
final class ExpeditionTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(sets: Int) -> CharacterProgress.SessionInput {
        CharacterProgress.SessionInput(completedAt: base, completedSets: sets, volumeKg: 1_000)
    }

    // MARK: - 元気

    func testNoWorkoutNoEnergy() {
        XCTAssertEqual(Expedition.totalEnergyEarned(sessions: []), 0)
        XCTAssertEqual(Expedition.energyEarned(for: session(sets: 0)), 0)
    }

    func testEnergyGrowsWithSetsUpToCap() {
        XCTAssertEqual(
            Expedition.energyEarned(for: session(sets: 5)),
            Expedition.energyPerSession + Expedition.energyPerSet * 5
        )
        XCTAssertEqual(Expedition.energyEarned(for: session(sets: 200)), Expedition.energyCapPerSession)
    }

    func testAvailableEnergySubtractsSpending() {
        let sessions = [session(sets: 10), session(sets: 10)]
        let earned = Expedition.totalEnergyEarned(sessions: sessions)
        XCTAssertEqual(Expedition.availableEnergy(sessions: sessions, spent: 20), earned - 20)
    }

    func testAvailableEnergyNeverGoesNegative() {
        XCTAssertEqual(Expedition.availableEnergy(sessions: [session(sets: 1)], spent: 10_000), 0)
        XCTAssertEqual(Expedition.availableEnergy(sessions: [], spent: -50), 0)
    }

    // MARK: - コース

    func testCoursesUnlockByLevel() {
        XCTAssertEqual(Expedition.unlockedCourses(level: 1).count, 1)
        XCTAssertEqual(Expedition.unlockedCourses(level: 99).count, Expedition.courses.count)
    }

    func testCourseLookup() {
        XCTAssertNotNil(Expedition.course(id: "morning-hill"))
        XCTAssertNil(Expedition.course(id: "not-a-course"))
    }

    // MARK: - 進行

    func testFinishDateUsesCourseDuration() {
        let course = Expedition.courses[0]
        let finish = Expedition.finishDate(startedAt: base, course: course)
        XCTAssertEqual(finish.timeIntervalSince(base), Double(course.durationMinutes) * 60, accuracy: 0.001)
    }

    func testProgressIsClampedToUnitRange() {
        let finish = base.addingTimeInterval(600)
        XCTAssertEqual(Expedition.progress(startedAt: base, finishesAt: finish, now: base), 0, accuracy: 0.0001)
        XCTAssertEqual(Expedition.progress(startedAt: base, finishesAt: finish, now: base.addingTimeInterval(300)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(Expedition.progress(startedAt: base, finishesAt: finish, now: base.addingTimeInterval(9_999)), 1, accuracy: 0.0001)
        XCTAssertEqual(Expedition.progress(startedAt: base, finishesAt: base, now: base), 1, accuracy: 0.0001)
    }

    func testRemainingSecondsAndText() {
        let finish = base.addingTimeInterval(3_600 * 2 + 1_800)
        XCTAssertEqual(Expedition.remainingSeconds(finishesAt: finish, now: base), 3_600 * 2 + 1_800)
        XCTAssertEqual(Expedition.remainingText(finishesAt: finish, now: base), "あと2時間30分")
        XCTAssertEqual(Expedition.remainingText(finishesAt: base.addingTimeInterval(1_800), now: base), "あと30分")
        XCTAssertEqual(Expedition.remainingText(finishesAt: base.addingTimeInterval(7_200), now: base), "あと2時間")
        XCTAssertEqual(Expedition.remainingText(finishesAt: base.addingTimeInterval(30), now: base), "まもなく帰還")
        XCTAssertEqual(Expedition.remainingText(finishesAt: base, now: base), "帰還済み")
    }

    func testRemainingSecondsIsZeroAfterFinish() {
        XCTAssertEqual(Expedition.remainingSeconds(finishesAt: base, now: base.addingTimeInterval(100)), 0)
    }

    // MARK: - 報酬

    /// 同じ遠征 id なら常に同じ報酬（受け取り前後や再表示でぶれない）。
    func testRewardIsDeterministic() {
        let seed = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
        let first = Expedition.reward(courseId: "iron-forest", seed: seed)
        let second = Expedition.reward(courseId: "iron-forest", seed: seed)
        XCTAssertEqual(first, second)
    }

    func testRewardDiffersAcrossSeeds() {
        let items = (0..<80).map { _ in Expedition.reward(courseId: "old-gym", seed: UUID()).id }
        XCTAssertGreaterThan(Set(items).count, 1, "毎回同じ装備しか出ないのは抽選が壊れている")
    }

    func testRewardAlwaysComesFromCatalog() {
        for _ in 0..<200 {
            let item = Expedition.reward(courseId: "summit", seed: UUID())
            XCTAssertNotNil(Expedition.item(id: item.id))
        }
    }

    /// 重みどおりに寄っているか（易しいコースはノーマル中心、難しいコースはレア以上が増える）。
    func testRarityFollowsCourseWeights() {
        func epicRate(_ courseId: String) -> Double {
            let trials = 600
            let epics = (0..<trials).filter { _ in
                Expedition.reward(courseId: courseId, seed: UUID()).rarity == .epic
            }.count
            return Double(epics) / Double(trials)
        }
        XCTAssertLessThan(epicRate("morning-hill"), epicRate("summit"))
    }

    func testUnknownCourseFallsBackSafely() {
        let item = Expedition.reward(courseId: "not-a-course", seed: UUID())
        XCTAssertNotNil(Expedition.item(id: item.id))
    }
}
