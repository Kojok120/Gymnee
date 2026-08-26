import XCTest
@testable import Gymnee

/// リカバリービュー（§6.8）のテスト。
final class RecoveryAnalyzerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func hoursAgo(_ h: Double) -> Date {
        now.addingTimeInterval(-h * 3600)
    }

    func testRecentlyTrainedNotRecovered() {
        // 二頭・三頭(arms)は回復48h。24h前 → 未回復、進捗0.5。
        let statuses = RecoveryAnalyzer.statuses(lastTrained: [.arms: hoursAgo(24)], asOf: now)
        let arms = statuses.first { $0.muscle == .arms }!
        XCTAssertFalse(arms.isRecovered)
        XCTAssertEqual(arms.recoveryProgress, 0.5, accuracy: 0.01)
    }

    func testFullyRestedIsRecovered() {
        // 脚は回復72h。80h前 → 回復済み。
        let statuses = RecoveryAnalyzer.statuses(lastTrained: [.legs: hoursAgo(80)], asOf: now)
        let legs = statuses.first { $0.muscle == .legs }!
        XCTAssertTrue(legs.isRecovered)
        XCTAssertEqual(legs.recoveryProgress, 1.0, accuracy: 0.0001)
    }

    func testUntrainedIsRecoveredCandidate() {
        let statuses = RecoveryAnalyzer.statuses(lastTrained: [:], asOf: now)
        XCTAssertTrue(statuses.allSatisfy { $0.isRecovered })
        XCTAssertTrue(statuses.allSatisfy { $0.lastTrained == nil })
    }
}
