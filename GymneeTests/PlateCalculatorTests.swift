import XCTest
@testable import Gymnee

/// バーベルのプレート換算のテスト。
final class PlateCalculatorTests: XCTestCase {

    func testExactBreakdown() {
        let b = PlateCalculator.breakdown(target: 100, bar: 20)
        XCTAssertEqual(b, PlateCalculator.Breakdown(perSide: [25, 15], remainder: 0))
    }

    func testSinglePlate() {
        let b = PlateCalculator.breakdown(target: 60, bar: 20)
        XCTAssertEqual(b, PlateCalculator.Breakdown(perSide: [20], remainder: 0))
    }

    func testBarOnly() {
        let b = PlateCalculator.breakdown(target: 20, bar: 20)
        XCTAssertEqual(b, PlateCalculator.Breakdown(perSide: [], remainder: 0))
    }

    func testRemainderWhenNotComposable() {
        // 61kg: 片側20.5 → 20 を載せて 0.5×2=1.0kg が端数。
        let b = PlateCalculator.breakdown(target: 61, bar: 20)
        XCTAssertEqual(b?.perSide, [20])
        XCTAssertEqual(b?.remainder ?? -1, 1.0, accuracy: 0.001)
    }

    func testSmallestPlateCombination() {
        // 47.5kg / バー15: 片側16.25 = 15 + 1.25。
        let b = PlateCalculator.breakdown(target: 47.5, bar: 15)
        XCTAssertEqual(b, PlateCalculator.Breakdown(perSide: [15, 1.25], remainder: 0))
    }

    func testBelowBarReturnsNil() {
        XCTAssertNil(PlateCalculator.breakdown(target: 15, bar: 20))
    }

    func testNonFiniteReturnsNil() {
        XCTAssertNil(PlateCalculator.breakdown(target: .infinity, bar: 20))
        XCTAssertNil(PlateCalculator.breakdown(target: 100, bar: .nan))
    }
}
