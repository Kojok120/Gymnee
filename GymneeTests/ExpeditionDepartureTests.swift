import XCTest
@testable import Gymnee

/// 遠征の出発と留守。「シートの中の進行バー」ではなく部屋の出来事にする、が要件。
final class ExpeditionDepartureTests: XCTestCase {

    private let runId = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
    private let start = CGPoint(x: 0.3, y: 0.6)

    // MARK: - 出発の歩き

    /// 出発するとドアへ向かって歩き、歩き終えたら姿を消す（＝不在が「遠征中」の表示になる）。
    func testWalksToTheDoorThenDisappears() {
        let begin = ExpeditionDeparture.pose(from: start, elapsed: 0)
        XCTAssertEqual(begin?.position.x ?? 0, start.x, accuracy: 0.001)
        XCTAssertEqual(begin?.behavior, .walking)

        let end = ExpeditionDeparture.pose(from: start, elapsed: ExpeditionDeparture.duration - 0.01)
        XCTAssertEqual(Double(end?.position.x ?? 0), Double(ExpeditionDeparture.doorSpot.x), accuracy: 0.02)

        XCTAssertNil(
            ExpeditionDeparture.pose(from: start, elapsed: ExpeditionDeparture.duration),
            "歩き終えても部屋に残っている"
        )
        XCTAssertNil(ExpeditionDeparture.pose(from: start, elapsed: -1))
    }

    /// ドアは右手にあるので、出発中は右を向く。
    func testFacesTheDoor() {
        XCTAssertEqual(ExpeditionDeparture.pose(from: start, elapsed: 0.5)?.facing, .right)
        // ドアより右にいた場合は左を向いて戻る。
        let fromRight = CGPoint(x: 0.98, y: 0.5)
        XCTAssertEqual(ExpeditionDeparture.pose(from: fromRight, elapsed: 0.5)?.facing, .left)
    }

    /// 位置がワープしない。
    func testWalkIsContinuous() {
        var previous = Double(start.x)
        for step in stride(from: 0.0, to: ExpeditionDeparture.duration, by: 0.05) {
            let x = Double(ExpeditionDeparture.pose(from: start, elapsed: step)?.position.x ?? 0)
            XCTAssertLessThan(abs(x - previous), 0.06, "elapsed=\(step) で飛んだ")
            previous = x
        }
    }

    // MARK: - 抱えていくグッズ

    /// 同じ遠征なら常に同じものを抱えていく（開き直すたびに持ち物が変わらない）。
    func testCarriedItemIsStablePerRun() {
        let a = ExpeditionDeparture.carriedItemId(seed: runId)
        XCTAssertEqual(a, ExpeditionDeparture.carriedItemId(seed: runId))
        XCTAssertTrue(ExpeditionDeparture.carriedItemIds.contains(a))
    }

    /// 遠征が変われば持ち物も変わりうる（毎回同じ絵にならない）。
    func testCarriedItemVariesAcrossRuns() {
        let seen = Set((0..<40).map { _ in ExpeditionDeparture.carriedItemId(seed: UUID()) })
        XCTAssertGreaterThan(seen.count, 1, "どの遠征でも同じものしか持っていかない")
    }

    // MARK: - 置き手紙

    func testLetterMentionsWhereAndWhen() {
        let text = ExpeditionDeparture.letterText(courseTitle: "鉄の森", remaining: "あと2時間", seed: runId)
        XCTAssertTrue(text.contains("鉄の森"), text)
        XCTAssertTrue(text.contains("あと2時間"), text)
    }

    /// 開くたびに文面が変わると嘘くさいので、遠征ごとに固定する。
    func testLetterIsStablePerRun() {
        let a = ExpeditionDeparture.letterText(courseTitle: "朝の丘", remaining: "あと29分", seed: runId)
        XCTAssertEqual(a, ExpeditionDeparture.letterText(courseTitle: "朝の丘", remaining: "あと29分", seed: runId))
    }

    func testLetterUsesEveryPattern() {
        let texts = Set((0..<80).map {
            _ in ExpeditionDeparture.letterText(courseTitle: "朝の丘", remaining: "あと29分", seed: UUID())
        })
        XCTAssertEqual(texts.count, ExpeditionDeparture.letterPatterns.count, "使われていない文面がある")
    }

    /// 「まもなく帰還」をそのまま埋めると「まもなく帰還で戻ります」になり日本語が壊れる。
    func testLetterHandlesImminentReturn() {
        for _ in 0..<20 {
            let text = ExpeditionDeparture.letterText(courseTitle: "朝の丘", remaining: "まもなく帰還", seed: UUID())
            XCTAssertFalse(text.contains("帰還で戻ります"), text)
            XCTAssertFalse(text.contains("帰還には帰ります"), text)
        }
    }

    func testEveryPatternHasBothPlaceholders() {
        for pattern in ExpeditionDeparture.letterPatterns {
            XCTAssertTrue(pattern.contains("%1$@"), pattern)
            XCTAssertTrue(pattern.contains("%2$@"), pattern)
        }
    }

    // MARK: - 配置

    /// ドアと手紙は床の内側（見切れない）。
    func testSpotsAreInsideTheRoom() {
        for spot in [ExpeditionDeparture.doorSpot, ExpeditionDeparture.letterSpot] {
            XCTAssertTrue((0.0...1.0).contains(Double(spot.x)))
            XCTAssertTrue((0.0...1.0).contains(Double(spot.y)))
        }
    }
}
