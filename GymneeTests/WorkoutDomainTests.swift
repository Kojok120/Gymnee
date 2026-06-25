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

/// PR 自動検出（§6.5）のテスト。
final class PRDetectorTests: XCTestCase {
    func testDetectsAllOnFirstSet() {
        let prs = PRDetector.detect(weight: 100, reps: 5, against: .init())
        let types = Set(prs.map(\.type))
        XCTAssertEqual(types, [.maxWeight, .maxReps, .est1RM, .maxVolume])
    }

    func testDetectsOnlyWeightWhenOthersLower() {
        // 既存: maxWeight90, maxReps10, est1RM130, maxVolume900
        let bests = PRDetector.Bests(maxWeight: 90, maxReps: 10, est1RM: 130, maxVolume: 900)
        // 新セット 95kg×3 → 重量更新(95>90), reps3<10, est=95*(1+3/30)=104.5<130, vol=285<900
        let prs = PRDetector.detect(weight: 95, reps: 3, against: bests)
        XCTAssertEqual(prs.map(\.type), [.maxWeight])
        XCTAssertEqual(prs.first?.value, 95)
    }

    func testNoPRWhenNothingBeaten() {
        let bests = PRDetector.Bests(maxWeight: 200, maxReps: 50, est1RM: 300, maxVolume: 5000)
        XCTAssertTrue(PRDetector.detect(weight: 100, reps: 5, against: bests).isEmpty)
    }
}
