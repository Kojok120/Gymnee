import XCTest
@testable import Gymnee

/// 推定 1RM（§6.5）のテスト。
final class OneRepMaxTests: XCTestCase {
    func testEpley() {
        // 100kg×5 → 100*(1+5/30)=116.67
        XCTAssertEqual(OneRepMax.estimate(weight: 100, reps: 5, formula: .epley), 116.666, accuracy: 0.01)
    }
    func testBrzycki() {
        // 100kg×5 → 100*36/(37-5)=112.5
        XCTAssertEqual(OneRepMax.estimate(weight: 100, reps: 5, formula: .brzycki), 112.5, accuracy: 0.01)
    }
    func testSingleRepReturnsWeight() {
        XCTAssertEqual(OneRepMax.estimate(weight: 120, reps: 1), 120, accuracy: 0.0001)
    }
    func testInvalidReturnsZero() {
        XCTAssertEqual(OneRepMax.estimate(weight: 0, reps: 5), 0)
        XCTAssertEqual(OneRepMax.estimate(weight: 100, reps: 0), 0)
    }
    func testBrzyckiHighRepFallsBack() {
        // reps>=37 で分母<=0 → Epley フォールバック（クラッシュしない）。
        XCTAssertGreaterThan(OneRepMax.estimate(weight: 50, reps: 40, formula: .brzycki), 0)
    }
}

/// ボリューム集計（§6.5）のテスト。
final class VolumeCalculatorTests: XCTestCase {
    private func entry(_ mg: MuscleGroup, _ w: Double, _ r: Int, _ d: Date = .now) -> VolumeCalculator.VolumeEntry {
        .init(muscleGroup: mg, weight: w, reps: r, date: d)
    }

    func testTotalVolume() {
        let entries = [
            entry(.chest, 100, 5),       // 500
            entry(.chest, 80, 8),        // 640
        ]
        XCTAssertEqual(VolumeCalculator.totalVolume(entries), 1140, accuracy: 0.0001)
    }

    func testVolumeByMuscle() {
        let entries = [
            entry(.chest, 100, 5),  // 500
            entry(.legs, 150, 5),   // 750
            entry(.chest, 80, 5),   // 400
        ]
        let byMuscle = VolumeCalculator.volumeByMuscle(entries)
        XCTAssertEqual(byMuscle[.chest] ?? 0, 900, accuracy: 0.0001)
        XCTAssertEqual(byMuscle[.legs] ?? 0, 750, accuracy: 0.0001)
    }

    func testSetCountByMuscle() {
        let entries = [
            entry(.chest, 100, 5),
            entry(.chest, 80, 8),
        ]
        XCTAssertEqual(VolumeCalculator.setCountByMuscle(entries)[.chest], 2)
    }
}

/// PR 自動検出（§6.5）のテスト。計測タイプごとに意味のある指標のみ判定する。
final class PRDetectorTests: XCTestCase {
    func testWeightDetectsMaxWeightAndEst1RMOnFirstSet() {
        let prs = PRDetector.detect(measurementType: .weight, weight: 100, reps: 5, durationSeconds: nil, against: .init())
        XCTAssertEqual(Set(prs.map(\.type)), [.maxWeight, .est1RM])
    }

    func testWeightDetectsOnlyMaxWeightWhenEst1RMLower() {
        // 既存: maxWeight90, est1RM130。新セット 95kg×3 → 重量更新(95>90), est=95*(1+3/30)=104.5<130
        let bests = PRDetector.Bests(maxWeight: 90, est1RM: 130)
        let prs = PRDetector.detect(measurementType: .weight, weight: 95, reps: 3, durationSeconds: nil, against: bests)
        XCTAssertEqual(prs.map(\.type), [.maxWeight])
        XCTAssertEqual(prs.first?.value, 95)
    }

    func testWeightDetectsOnlyEst1RMWhenWeightTied() {
        // 同じ重量でレップが伸びた → 最大重量は更新しないが推定1RMは更新する
        let bests = PRDetector.Bests(maxWeight: 100, est1RM: 110)
        let prs = PRDetector.detect(measurementType: .weight, weight: 100, reps: 6, durationSeconds: nil, against: bests)
        XCTAssertEqual(prs.map(\.type), [.est1RM])
    }

    func testWeightIgnoresRepsAndDuration() {
        // ウェイト種目では、レップ/時間が大きくても maxReps・maxDuration は出さない。
        // 重量・推定1RM は十分高いベストを置いて発火させず、軸が無視されることだけを検証する。
        let bests = PRDetector.Bests(maxWeight: 999, est1RM: 9999)
        let prs = PRDetector.detect(measurementType: .weight, weight: 80, reps: 99, durationSeconds: 9999, against: bests)
        XCTAssertFalse(prs.contains { $0.type == .maxReps || $0.type == .maxDuration })
        XCTAssertTrue(prs.isEmpty)
    }

    func testBodyweightDetectsOnlyMaxReps() {
        let prs = PRDetector.detect(measurementType: .bodyweight, weight: 0, reps: 12, durationSeconds: nil, against: .init())
        XCTAssertEqual(prs.map(\.type), [.maxReps])
        XCTAssertEqual(prs.first?.value, 12)
    }

    func testBodyweightNoPRWhenRepsNotBeaten() {
        let bests = PRDetector.Bests(maxReps: 20)
        XCTAssertTrue(PRDetector.detect(measurementType: .bodyweight, weight: 0, reps: 15, durationSeconds: nil, against: bests).isEmpty)
    }

    func testTimeDetectsMaxDuration() {
        let prs = PRDetector.detect(measurementType: .time, weight: 0, reps: 0, durationSeconds: 90, against: .init())
        XCTAssertEqual(prs.map(\.type), [.maxDuration])
        XCTAssertEqual(prs.first?.value, 90)
    }

    func testTimeNoPRWhenDurationNotBeaten() {
        let bests = PRDetector.Bests(maxDuration: 120)
        XCTAssertTrue(PRDetector.detect(measurementType: .time, weight: 0, reps: 0, durationSeconds: 90, against: bests).isEmpty)
    }

    func testNoPRWhenNothingBeaten() {
        let bests = PRDetector.Bests(maxWeight: 200, est1RM: 300)
        XCTAssertTrue(PRDetector.detect(measurementType: .weight, weight: 100, reps: 5, durationSeconds: nil, against: bests).isEmpty)
    }
}
