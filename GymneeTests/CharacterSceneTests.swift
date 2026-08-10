import XCTest
@testable import Gymnee

/// キャラの徘徊ロジック。時刻から決定的に姿勢を出すため、
/// 「同じ入力なら同じ結果」「範囲を外れない」「区間の境目で位置が飛ばない」の 3 点を守る。
final class CharacterSceneTests: XCTestCase {

    private let seed: UInt64 = 0xDEAD_BEEF

    // MARK: - 決定性

    func testPoseIsDeterministic() {
        for t in stride(from: 0.0, through: 60.0, by: 3.7) {
            let a = CharacterScene.pose(at: t, seed: seed)
            let b = CharacterScene.pose(at: t, seed: seed)
            XCTAssertEqual(a, b, "t=\(t) で結果が揺れた")
        }
    }

    func testDifferentSeedsProduceDifferentPaths() {
        let a = (0..<20).map { CharacterScene.pose(at: Double($0) * 2, seed: 1).position }
        let b = (0..<20).map { CharacterScene.pose(at: Double($0) * 2, seed: 2).position }
        XCTAssertNotEqual(a, b, "シードを変えても同じ経路になっている")
    }

    // MARK: - 範囲

    func testPositionStaysInsideWalkableArea() {
        for t in stride(from: 0.0, through: 500.0, by: 0.37) {
            let pose = CharacterScene.pose(at: t, seed: seed)
            XCTAssertTrue(
                CharacterScene.xRange.contains(Double(pose.position.x)),
                "t=\(t) で x が範囲外: \(pose.position.x)"
            )
            XCTAssertTrue(
                CharacterScene.yRange.contains(Double(pose.position.y)),
                "t=\(t) で y が範囲外: \(pose.position.y)"
            )
        }
    }

    func testPhasesStayNormalized() {
        for t in stride(from: 0.0, through: 200.0, by: 0.13) {
            let pose = CharacterScene.pose(at: t, seed: seed)
            XCTAssertTrue((0...1).contains(pose.walkPhase), "walkPhase=\(pose.walkPhase)")
            XCTAssertTrue((0...1).contains(pose.emotePhase), "emotePhase=\(pose.emotePhase)")
            XCTAssertTrue((0...1).contains(pose.blink), "blink=\(pose.blink)")
            XCTAssertTrue((-1...1).contains(pose.breathPhase), "breathPhase=\(pose.breathPhase)")
        }
    }

    func testNegativeTimeIsClampedNotCrashing() {
        let pose = CharacterScene.pose(at: -50, seed: seed)
        XCTAssertTrue(CharacterScene.xRange.contains(Double(pose.position.x)))
        XCTAssertTrue(CharacterScene.yRange.contains(Double(pose.position.y)))
    }

    // MARK: - 連続性

    /// 区間の境目でワープしないこと。境目の直前と直後で位置がほぼ同じであるべき。
    func testPositionIsContinuousAcrossSegmentBoundaries() {
        let step = CharacterScene.segmentDuration
        for index in 0..<25 {
            let boundary = Double(index) * step
            let before = CharacterScene.pose(at: boundary - 0.001, seed: seed).position
            let after = CharacterScene.pose(at: boundary + 0.001, seed: seed).position
            let dx = Double(after.x - before.x)
            let dy = Double(after.y - before.y)
            let jump = (dx * dx + dy * dy).squareRoot()
            XCTAssertLessThan(jump, 0.01, "区間 \(index) の境目で \(jump) だけワープした")
        }
    }

    /// 歩いている間の位置も飛ばないこと（イージングが単調に効いている）。
    func testWalkIsSmooth() {
        var previous = CharacterScene.pose(at: 0, seed: seed).position
        for t in stride(from: 0.02, through: 40.0, by: 0.02) {
            let current = CharacterScene.pose(at: t, seed: seed).position
            let dx = Double(current.x - previous.x)
            let dy = Double(current.y - previous.y)
            XCTAssertLessThan((dx * dx + dy * dy).squareRoot(), 0.02, "t=\(t) で急に飛んだ")
            previous = current
        }
    }

    // MARK: - 向き

    /// 移動ベクトルから向きが決まる。y は 0＝奥 / 1＝手前なので、手前へ進む＝こちらを向く。
    func testFacingFromMovement() {
        func facing(_ dx: Double, _ dy: Double) -> CharacterScene.Facing {
            CharacterScene.facing(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.5 + dx, y: 0.5 + dy))
        }
        XCTAssertEqual(facing(0.3, 0.0), .right)
        XCTAssertEqual(facing(-0.3, 0.0), .left)
        XCTAssertEqual(facing(0.0, 0.3), .down)
        XCTAssertEqual(facing(0.0, -0.3), .up)
        // 縦横が拮抗したときは横を優先する（輪郭が変わって歩いて見えるため）。
        XCTAssertEqual(facing(0.2, 0.2), .right)
        XCTAssertEqual(facing(-0.2, -0.2), .left)
        // 斜めでも支配的な軸に寄る。
        XCTAssertEqual(facing(0.1, -0.4), .up)
    }

    func testWalkFacingMatchesMovement() {
        // 歩いている最中は、必ず進行方向を向いている。
        for t in stride(from: 0.0, through: 200.0, by: 0.25) {
            let pose = CharacterScene.pose(at: t, seed: seed)
            guard pose.behavior == .walking else { continue }
            let next = CharacterScene.pose(at: t + 0.25, seed: seed)
            guard next.behavior == .walking else { continue }
            let dx = Double(next.position.x - pose.position.x)
            let dy = Double(next.position.y - pose.position.y)
            guard abs(dx) > 0.002 || abs(dy) > 0.002 else { continue }
            switch pose.facing {
            case .right: XCTAssertGreaterThan(dx, -0.0001, "t=\(t)")
            case .left: XCTAssertLessThan(dx, 0.0001, "t=\(t)")
            case .down: XCTAssertGreaterThan(dy, -0.0001, "t=\(t)")
            case .up: XCTAssertLessThan(dy, 0.0001, "t=\(t)")
            }
        }
    }

    /// 仕草の間は必ずこちらを向く（背中を向けたまま腕立てされても伝わらない）。
    func testEmotingAlwaysFacesViewer() {
        for t in stride(from: 0.0, through: 300.0, by: 0.21) {
            let pose = CharacterScene.pose(at: t, seed: seed)
            if case .emoting = pose.behavior {
                XCTAssertEqual(pose.facing, .down, "t=\(t) で仕草中に横／背を向けている")
            }
        }
    }

    func testFacingMirrorFlags() {
        XCTAssertTrue(CharacterScene.Facing.left.isSideways)
        XCTAssertTrue(CharacterScene.Facing.right.isSideways)
        XCTAssertFalse(CharacterScene.Facing.up.isSideways)
        XCTAssertFalse(CharacterScene.Facing.down.isSideways)
        // 横向きの絵は右向きで持ち、左向きだけ反転する。
        XCTAssertTrue(CharacterScene.Facing.left.isMirrored)
        XCTAssertFalse(CharacterScene.Facing.right.isMirrored)
    }

    // MARK: - まばたき

    func testBlinkClosesOncePerPeriod() {
        // 1 周期のうち、閉じている時間はごく短い。
        var closedSamples = 0
        var total = 0
        for t in stride(from: 0.0, to: CharacterScene.blinkPeriod * 20, by: 0.01) {
            total += 1
            if CharacterScene.blink(at: t, seed: seed) > 0.5 { closedSamples += 1 }
        }
        let ratio = Double(closedSamples) / Double(total)
        XCTAssertGreaterThan(ratio, 0, "一度もまばたきしていない")
        XCTAssertLessThan(ratio, 0.10, "閉じている時間が長すぎる（\(ratio)）")
    }

    // MARK: - 奥行き

    func testDepthScaleGrowsTowardViewer() {
        XCTAssertLessThan(CharacterScene.depthScale(0), CharacterScene.depthScale(1))
        XCTAssertEqual(CharacterScene.depthScale(-5), CharacterScene.depthScale(0), accuracy: 0.0001)
        XCTAssertEqual(CharacterScene.depthScale(9), CharacterScene.depthScale(1), accuracy: 0.0001)
    }

    // MARK: - 時間帯

    func testTimeOfDayBuckets() {
        func at(_ hour: Int) -> CharacterScene.TimeOfDay {
            var components = DateComponents()
            components.year = 2026
            components.month = 8
            components.day = 10
            components.hour = hour
            let date = Calendar.current.date(from: components)!
            return CharacterScene.timeOfDay(at: date)
        }
        XCTAssertEqual(at(3), .night)
        XCTAssertEqual(at(7), .dawn)
        XCTAssertEqual(at(12), .day)
        XCTAssertEqual(at(17), .dusk)
        XCTAssertEqual(at(22), .night)
    }

    // MARK: - 決定的乱数

    func testDeterministicRandomIsStableAndBounded() {
        var a = DeterministicRandom(seed: 42)
        var b = DeterministicRandom(seed: 42)
        for _ in 0..<50 {
            let value = a.unit()
            XCTAssertEqual(value, b.unit())
            XCTAssertTrue((0..<1).contains(value), "unit() が 0..<1 を外れた: \(value)")
        }
    }

    func testSeedFromUUIDIsStable() {
        let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
        XCTAssertEqual(DeterministicRandom.seed(from: id), DeterministicRandom.seed(from: id))
        XCTAssertNotEqual(DeterministicRandom.seed(from: id), DeterministicRandom.seed(from: UUID()))
    }
}
