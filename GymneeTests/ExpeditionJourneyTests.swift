import XCTest
@testable import Gymnee

/// 道中の出来事と合トレ補正のテスト。
final class ExpeditionJourneyTests: XCTestCase {

    private let seed = UUID(uuidString: "9F8E7D6C-5B4A-3928-1706-F5E4D3C2B1A0")!

    func testEventsAreDeterministic() {
        let first = ExpeditionJourney.events(courseId: "iron-forest", seed: seed)
        let second = ExpeditionJourney.events(courseId: "iron-forest", seed: seed)
        XCTAssertEqual(first, second, "同じ遠征なら何度開いても同じ物語になる")
    }

    func testEventCountIsThreeOrFour() {
        for _ in 0..<50 {
            let events = ExpeditionJourney.events(courseId: "summit", seed: UUID())
            XCTAssertTrue((3...4).contains(events.count), "件数が \(events.count) 件")
        }
    }

    func testEventsHaveNoDuplicates() {
        for _ in 0..<50 {
            let events = ExpeditionJourney.events(courseId: "old-gym", seed: UUID())
            XCTAssertEqual(Set(events.map(\.text)).count, events.count, "同じ出来事が二重に出ている")
        }
    }

    func testCoopAlwaysIncludesPartnerEvent() {
        for _ in 0..<30 {
            let events = ExpeditionJourney.events(courseId: "morning-hill", seed: UUID(), coop: true)
            XCTAssertTrue(events.contains { $0.text.contains("仲間") }, "共闘なら仲間の出来事が混ざる")
        }
    }

    func testUnknownCourseStillProducesEvents() {
        XCTAssertFalse(ExpeditionJourney.events(courseId: "no-such-course", seed: seed).isEmpty)
    }

    func testEventIdsAreSequential() {
        let events = ExpeditionJourney.events(courseId: "iron-forest", seed: seed)
        XCTAssertEqual(events.map(\.id), Array(0..<events.count))
    }

    // MARK: - 合トレ補正

    func testCoopRaisesRareAndEpicWeights() {
        let base = [80, 18, 2]
        let boosted = Expedition.boosted(base)
        XCTAssertEqual(boosted[0], base[0], "ノーマルの重みは変えない")
        XCTAssertGreaterThan(boosted[1], base[1])
        XCTAssertGreaterThan(boosted[2], base[2])
    }

    func testCoopMakesGoodItemsMoreLikely() {
        func epicRate(coop: Bool) -> Double {
            let trials = 600
            let hits = (0..<trials).filter { _ in
                Expedition.reward(courseId: "iron-forest", seed: UUID(), coop: coop).rarity == .epic
            }.count
            return Double(hits) / Double(trials)
        }
        XCTAssertGreaterThan(epicRate(coop: true), epicRate(coop: false))
    }

    func testRewardStaysDeterministicPerCoopFlag() {
        let a = Expedition.reward(courseId: "summit", seed: seed, coop: true)
        let b = Expedition.reward(courseId: "summit", seed: seed, coop: true)
        XCTAssertEqual(a, b)
    }
}
