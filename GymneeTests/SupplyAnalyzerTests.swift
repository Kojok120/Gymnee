import XCTest
@testable import Gymnee

/// 補給ロギング→在庫リマインド（§6.12）のテスト。
final class SupplyAnalyzerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

    func testRemainingAndRate() {
        // 10日間で20回消費 → 1日2回。1容器=33回×1容器 → 残り13。
        let logs = (0..<10).map { SupplyAnalyzer.LogPoint(date: daysAgo(Double(10 - $0)), amount: 2) }
        let est = SupplyAnalyzer.estimate(logs: logs, servingsPerUnit: 33, unitsPurchased: 1, asOf: now)
        XCTAssertEqual(est.consumedTotal, 20, accuracy: 0.001)
        XCTAssertEqual(est.dailyRate, 2, accuracy: 0.2)
        XCTAssertEqual(est.remaining ?? -1, 13, accuracy: 0.001)
        XCTAssertNotNil(est.daysUntilEmpty)
    }

    func testIsLowWhenSoonEmpty() {
        // 1日3回、1容器=33回。30回消費済 → 残り3 → 約1日で枯渇 → low。
        let logs = (0..<10).map { SupplyAnalyzer.LogPoint(date: daysAgo(Double(10 - $0)), amount: 3) }
        let est = SupplyAnalyzer.estimate(logs: logs, servingsPerUnit: 33, unitsPurchased: 1, asOf: now)
        XCTAssertTrue(est.isLow)
    }

    func testNotLowWhenPlenty() {
        // 少量消費・大量在庫 → low でない。
        let logs = [SupplyAnalyzer.LogPoint(date: daysAgo(5), amount: 2)]
        let est = SupplyAnalyzer.estimate(logs: logs, servingsPerUnit: 100, unitsPurchased: 2, asOf: now)
        XCTAssertFalse(est.isLow)
        XCTAssertEqual(est.remaining ?? -1, 198, accuracy: 0.001)
    }

    func testEmptyLogs() {
        let est = SupplyAnalyzer.estimate(logs: [], servingsPerUnit: 33, unitsPurchased: 1, asOf: now)
        XCTAssertEqual(est.consumedTotal, 0)
        XCTAssertFalse(est.isLow)
        XCTAssertNil(est.daysUntilEmpty)
    }

    func testRunsOutWhenConsumedExceedsStock() {
        let logs = [SupplyAnalyzer.LogPoint(date: daysAgo(10), amount: 40)]
        let est = SupplyAnalyzer.estimate(logs: logs, servingsPerUnit: 33, unitsPurchased: 1, asOf: now)
        XCTAssertEqual(est.remaining ?? -1, 0, accuracy: 0.001)
        XCTAssertTrue(est.isLow)
    }
}
