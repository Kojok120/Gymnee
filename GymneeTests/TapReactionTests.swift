import XCTest
@testable import Gymnee

/// 触ったときの反応。進行には一切影響させず、見た目だけ返す。
final class TapReactionTests: XCTestCase {

    private let feet = CGPoint(x: 200, y: 500)
    private let side: CGFloat = 100

    // MARK: - 当たり判定

    func testHitsOnTheBody() {
        // 足元・胴・頭のあたりはすべて当たる。
        XCTAssertTrue(TapReaction.isHit(tap: CGPoint(x: 200, y: 495), feet: feet, size: side))
        XCTAssertTrue(TapReaction.isHit(tap: CGPoint(x: 200, y: 450), feet: feet, size: side))
        XCTAssertTrue(TapReaction.isHit(tap: CGPoint(x: 200, y: 410), feet: feet, size: side))
    }

    func testMissesFarAway() {
        XCTAssertFalse(TapReaction.isHit(tap: CGPoint(x: 20, y: 500), feet: feet, size: side))
        XCTAssertFalse(TapReaction.isHit(tap: CGPoint(x: 200, y: 100), feet: feet, size: side))
        XCTAssertFalse(TapReaction.isHit(tap: CGPoint(x: 200, y: 700), feet: feet, size: side))
    }

    /// 指で狙える程度に判定を広めに取っている（細いキャラを正確に突かせない）。
    func testHitAreaIsForgiving() {
        let edge = CGPoint(x: feet.x + side * 0.4, y: feet.y - side * 0.5)
        XCTAssertTrue(TapReaction.isHit(tap: edge, feet: feet, size: side))
    }

    func testZeroSizeNeverHits() {
        XCTAssertFalse(TapReaction.isHit(tap: feet, feet: feet, size: 0))
    }

    /// ペットは絵が小さいので、判定を広げて指で狙えるようにしてある。
    func testPetRadiusIsWiderThanTheDefault() {
        XCTAssertGreaterThan(TapReaction.petHitRadiusRatio, TapReaction.hitRadiusRatio)
        // 既定では外れる位置でも、ペットの判定なら当たる。
        // 既定の半幅は size * 0.75 / 2 に 10% の余白を足して 47.5、ペットは同様に 67.5。
        let justOutside = CGPoint(x: feet.x + side * 0.55, y: feet.y - side * 0.5)
        XCTAssertFalse(TapReaction.isHit(tap: justOutside, feet: feet, size: side))
        XCTAssertTrue(TapReaction.isHit(tap: justOutside, feet: feet, size: side,
                                        radiusRatio: TapReaction.petHitRadiusRatio))
    }

    // MARK: - 反応の状態（対象ごとに 1 つ持つ）

    func testFireAdvancesTheParticleAndStampsTime() {
        var state = TapReaction.State()
        XCTAssertNil(state.at)
        XCTAssertNil(state.elapsed(.now))

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        state.fire(now: now)
        XCTAssertEqual(state.count, 1)
        XCTAssertEqual(state.at, now)
        XCTAssertEqual(state.elapsed(now.addingTimeInterval(0.5)) ?? -1, 0.5, accuracy: 0.001)
    }

    /// 同じ絵が続くと反応が単調に見えるので、押すたびに巡回する。
    func testParticleCyclesThroughAllOfThem() {
        var state = TapReaction.State()
        var seen: [TapReaction.Particle] = []
        for _ in 0..<TapReaction.Particle.allCases.count {
            state.fire()
            seen.append(state.particle)
        }
        XCTAssertEqual(Set(seen).count, TapReaction.Particle.allCases.count, "同じ絵ばかり出ている")
    }

    func testParticleNextIsStableForNegativeCounts() {
        XCTAssertEqual(TapReaction.Particle.next(count: -1), TapReaction.Particle.next(count: 1))
    }

    // MARK: - 浮かぶ絵

    func testParticleFollowsTheReactionWindow() {
        XCTAssertNotNil(TapReaction.particleProgress(elapsed: 0))
        XCTAssertNotNil(TapReaction.particleProgress(elapsed: TapReaction.duration - 0.01))
        XCTAssertNil(TapReaction.particleProgress(elapsed: TapReaction.duration))
        XCTAssertNil(TapReaction.particleProgress(elapsed: -1))
    }

    /// 出た瞬間は不透明、終わりに向けて消える（最後に急に消えない）。
    func testParticleFadesOutTowardTheEnd() {
        XCTAssertEqual(TapReaction.particleOpacity(progress: 0), 1, accuracy: 0.001)
        XCTAssertEqual(TapReaction.particleOpacity(progress: 0.5), 1, accuracy: 0.001)
        XCTAssertLessThan(TapReaction.particleOpacity(progress: 0.8), 1)
        XCTAssertEqual(TapReaction.particleOpacity(progress: 1), 0, accuracy: 0.001)
    }

    func testParticleRisesAndSlowsDown() {
        let early = TapReaction.particleRise(progress: 0.2) - TapReaction.particleRise(progress: 0)
        let late = TapReaction.particleRise(progress: 1) - TapReaction.particleRise(progress: 0.8)
        XCTAssertGreaterThan(early, late, "上ほど緩やかに上がる")
        XCTAssertEqual(TapReaction.particleRise(progress: 0), 0, accuracy: 0.001)
    }
}
