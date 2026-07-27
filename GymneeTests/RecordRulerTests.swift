import XCTest
@testable import Gymnee

/// 記録ルーラーの値列（区分刻み・符号付き自重軸）と符号付きPR判定のテスト。
@MainActor
final class RecordRulerTests: XCTestCase {

    // MARK: - 区分刻み（純関数）

    /// ダンベル: 10kg までは 1kg 刻み、10kg 超は偶数の 2kg 刻み。
    func testDumbbellPiecewiseValues() {
        let values = RecordSlots.piecewiseValues(segments: [(0, 10, 1), (10, 60, 2)], center: 8)
        XCTAssertTrue(values.contains(7))
        XCTAssertTrue(values.contains(9))
        XCTAssertTrue(values.contains(10))
        XCTAssertTrue(values.contains(12))
        XCTAssertTrue(values.contains(14))
        XCTAssertFalse(values.contains(11))
        XCTAssertFalse(values.contains(13))
    }

    /// グリッド外の学習値（キーパッド入力）は必ず値列に含まれる。
    func testPiecewiseIncludesOffGridCenter() {
        let values = RecordSlots.piecewiseValues(segments: [(0, 10, 1), (10, 60, 2)], center: 12.5)
        XCTAssertTrue(values.contains(12.5))
    }

    /// 範囲外の大きな center は端の刻みで延長される。
    func testPiecewiseExtendsBeyondRange() {
        let values = RecordSlots.piecewiseValues(segments: [(0, 10, 1), (10, 60, 2)], center: 70)
        XCTAssertTrue(values.contains(70))
        XCTAssertTrue(values.contains(62))
    }

    /// 自重の一本軸: 補助側は 5kg 刻み・加重側は 2.5kg 刻み・0（自重）を含む。
    func testSignedLoadAxisValues() {
        let values = RecordSlots.piecewiseValues(segments: [(-60, 0, 5), (0, 60, 2.5)], center: -15)
        XCTAssertTrue(values.contains(0))
        XCTAssertTrue(values.contains(-15))
        XCTAssertTrue(values.contains(-5))
        XCTAssertFalse(values.contains(-2.5))  // 補助側は5kg刻み
        XCTAssertTrue(values.contains(2.5))    // 加重側は2.5kg刻み
    }

    // MARK: - 角度ルーラー（0〜60°・5°刻み）

    func testAngleRulerValuesFixedRange() {
        let values = RecordSlots.angleRulerValues(center: 30)
        XCTAssertEqual(values.first, 0)
        XCTAssertEqual(values.last, 60)
        XCTAssertTrue(values.contains(30))
        XCTAssertTrue(values.contains(45))
        XCTAssertFalse(values.contains(65))   // 上限60
        XCTAssertFalse(values.contains(32))    // 5°刻み
    }

    func testAngleRulerClampsOutOfRangeCenter() {
        // 範囲外の center は 0〜60 に丸めて含める（不正値がDBの check を越えない）。
        XCTAssertEqual(RecordSlots.angleRulerValues(center: 100).last, 60)
        XCTAssertEqual(RecordSlots.angleRulerValues(center: -10).first, 0)
    }

    // MARK: - セット表示への角度前置

    func testDetailTextPrependsAngle() {
        let set = ExerciseSet(setIndex: 0, weight: 60, reps: 10, angleDegrees: 30)
        XCTAssertEqual(set.detailText, "30° · 60kg × 10")
    }

    func testDetailTextWithoutAngleUnchanged() {
        let set = ExerciseSet(setIndex: 0, weight: 60, reps: 10)
        XCTAssertEqual(set.detailText, "60kg × 10")
    }

    // MARK: - 符号付きPR判定（自重の加重/補助）

    func testAssistPRWithSignedWeight() {
        // 補助15kg → 補助10kg は PR（補助が小さいほど強い）。
        var bests = PRDetector.Bests()
        bests.minAssist = 15
        let prs = PRDetector.detect(measurementType: .bodyweight, weight: -10, reps: 5,
                                    durationSeconds: nil, against: bests, loadMode: .assisted)
        XCTAssertEqual(prs, [PRDetector.DetectedPR(type: .minAssist, value: 10)])
    }

    func testBodyweightZeroBeatsAssist() {
        // 補助5kg → 自重(0) は PR（value 0）。
        var bests = PRDetector.Bests()
        bests.minAssist = 5
        let prs = PRDetector.detect(measurementType: .bodyweight, weight: 0, reps: 3,
                                    durationSeconds: nil, against: bests, loadMode: .assisted)
        XCTAssertEqual(prs, [PRDetector.DetectedPR(type: .minAssist, value: 0)])
    }

    func testWeightedPRAfterAssistHistory() {
        // 補助履歴のみ（maxWeight=0）から初の加重 +2.5kg は最大荷重 PR。
        var bests = PRDetector.Bests()
        bests.minAssist = 10
        let prs = PRDetector.detect(measurementType: .bodyweight, weight: 2.5, reps: 5,
                                    durationSeconds: nil, against: bests, loadMode: .assisted)
        XCTAssertEqual(prs, [PRDetector.DetectedPR(type: .maxWeight, value: 2.5)])
    }

    func testLargerAssistIsNotPR() {
        var bests = PRDetector.Bests()
        bests.minAssist = 10
        let prs = PRDetector.detect(measurementType: .bodyweight, weight: -20, reps: 8,
                                    durationSeconds: nil, against: bests, loadMode: .assisted)
        XCTAssertTrue(prs.isEmpty)
    }
}
