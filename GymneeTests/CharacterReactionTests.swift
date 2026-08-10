import XCTest
@testable import Gymnee

/// キャラをタップしたときの反応。進行には一切影響させず、見た目だけ返す。
final class CharacterReactionTests: XCTestCase {

    private let feet = CGPoint(x: 200, y: 500)
    private let side: CGFloat = 100

    // MARK: - 当たり判定

    func testHitsOnTheBody() {
        // 足元・胴・頭のあたりはすべて当たる。
        XCTAssertTrue(CharacterReaction.isHit(tap: CGPoint(x: 200, y: 495), feet: feet, size: side))
        XCTAssertTrue(CharacterReaction.isHit(tap: CGPoint(x: 200, y: 450), feet: feet, size: side))
        XCTAssertTrue(CharacterReaction.isHit(tap: CGPoint(x: 200, y: 410), feet: feet, size: side))
    }

    func testMissesFarAway() {
        XCTAssertFalse(CharacterReaction.isHit(tap: CGPoint(x: 20, y: 500), feet: feet, size: side))
        XCTAssertFalse(CharacterReaction.isHit(tap: CGPoint(x: 200, y: 100), feet: feet, size: side))
        XCTAssertFalse(CharacterReaction.isHit(tap: CGPoint(x: 200, y: 700), feet: feet, size: side))
    }

    /// 指で狙える程度に judgement を広めに取っている（細いキャラを正確に突かせない）。
    func testHitAreaIsForgiving() {
        let edge = CGPoint(x: feet.x + side * 0.4, y: feet.y - side * 0.5)
        XCTAssertTrue(CharacterReaction.isHit(tap: edge, feet: feet, size: side))
    }

    func testZeroSizeNeverHits() {
        XCTAssertFalse(CharacterReaction.isHit(tap: feet, feet: feet, size: 0))
    }

    // MARK: - 姿勢

    /// 位置と向き以外を差し替える。歩いている途中でも立ち位置は動かさない。
    func testReactionKeepsPositionAndFacesViewer() {
        let base = CharacterScene.Pose(
            position: CGPoint(x: 0.7, y: 0.3), facing: .left, behavior: .walking,
            walkPhase: 0.5, emotePhase: 0, breathPhase: 0, blink: 0
        )
        let reacting = CharacterReaction.pose(base: base, elapsed: 0.2)
        XCTAssertEqual(reacting?.position, base.position, "反応で立ち位置が動いた")
        XCTAssertEqual(reacting?.facing, .down, "触られたらこちらを向く")
        XCTAssertEqual(reacting?.behavior, .emoting(.cheer))
    }

    func testReactionEndsAfterDuration() {
        let base = CharacterScene.Pose(
            position: .zero, facing: .down, behavior: .walking,
            walkPhase: 0, emotePhase: 0, breathPhase: 0, blink: 0
        )
        XCTAssertNotNil(CharacterReaction.pose(base: base, elapsed: CharacterReaction.duration - 0.01))
        XCTAssertNil(CharacterReaction.pose(base: base, elapsed: CharacterReaction.duration))
        XCTAssertNil(CharacterReaction.pose(base: base, elapsed: -1))
    }

    func testEmotePhaseAdvancesMonotonically() {
        let base = CharacterScene.Pose(
            position: .zero, facing: .down, behavior: .walking,
            walkPhase: 0, emotePhase: 0, breathPhase: 0, blink: 0
        )
        var previous = -1.0
        for step in stride(from: 0.0, to: CharacterReaction.duration, by: 0.05) {
            let phase = CharacterReaction.pose(base: base, elapsed: step)?.emotePhase ?? -1
            XCTAssertGreaterThanOrEqual(phase, previous)
            XCTAssertTrue((0...1).contains(phase))
            previous = phase
        }
    }

    // MARK: - 浮かぶ絵

    func testParticleFollowsTheReactionWindow() {
        XCTAssertNotNil(CharacterReaction.particleProgress(elapsed: 0))
        XCTAssertNotNil(CharacterReaction.particleProgress(elapsed: CharacterReaction.duration - 0.01))
        XCTAssertNil(CharacterReaction.particleProgress(elapsed: CharacterReaction.duration))
    }

    /// 出た瞬間は不透明、終わりに向けて消える（最後に急に消えない）。
    func testParticleFadesOutTowardTheEnd() {
        XCTAssertEqual(CharacterReaction.particleOpacity(progress: 0), 1, accuracy: 0.001)
        XCTAssertEqual(CharacterReaction.particleOpacity(progress: 0.5), 1, accuracy: 0.001)
        XCTAssertLessThan(CharacterReaction.particleOpacity(progress: 0.8), 1)
        XCTAssertEqual(CharacterReaction.particleOpacity(progress: 1), 0, accuracy: 0.001)
    }

    func testParticleRisesAndSlowsDown() {
        let early = CharacterReaction.particleRise(progress: 0.2) - CharacterReaction.particleRise(progress: 0)
        let late = CharacterReaction.particleRise(progress: 1) - CharacterReaction.particleRise(progress: 0.8)
        XCTAssertGreaterThan(early, late, "上に行くほど緩やかにならない")
        XCTAssertEqual(CharacterReaction.particleRise(progress: 0), 0, accuracy: 0.001)
    }

    /// タップのたびに絵が変わる（同じ反応の繰り返しに見せない）。
    func testParticleCyclesThroughVariants() {
        let sequence = (0..<6).map { CharacterReaction.Particle.next(count: $0) }
        XCTAssertEqual(Set(sequence).count, CharacterReaction.Particle.allCases.count)
        XCTAssertNotEqual(sequence[0], sequence[1])
    }
}
