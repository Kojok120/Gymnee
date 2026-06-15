import XCTest
@testable import Gymnee

/// リカバリービュー（§6.8）のテスト。
final class RecoveryAnalyzerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func hoursAgo(_ h: Double) -> Date {
        now.addingTimeInterval(-h * 3600)
    }

    func testRecentlyTrainedNotRecovered() {
        // 二頭は回復48h。24h前 → 未回復、進捗0.5。
        let statuses = RecoveryAnalyzer.statuses(lastTrained: [.biceps: hoursAgo(24)], asOf: now)
        let biceps = statuses.first { $0.muscle == .biceps }!
        XCTAssertFalse(biceps.isRecovered)
        XCTAssertEqual(biceps.recoveryProgress, 0.5, accuracy: 0.01)
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

    func testRecommendedNextPrioritizesUntrainedThenLongestRest() {
        let lastTrained: [MuscleGroup: Date] = [
            .chest: hoursAgo(10),   // 未回復
            .back: hoursAgo(100),   // 回復済み・長休
            .legs: hoursAgo(80),    // 回復済み
            // biceps は未訓練 → 最優先
        ]
        let statuses = RecoveryAnalyzer.statuses(lastTrained: lastTrained, asOf: now)
        let next = RecoveryAnalyzer.recommendedNext(from: statuses)
        // chest は未回復なので除外される。
        XCTAssertFalse(next.contains(.chest))
        // 未訓練(biceps/triceps/shoulders/core/glutes)が先頭群、その後 back > legs。
        XCTAssertTrue(next.contains(.back))
        XCTAssertTrue(next.contains(.legs))
        if let backIdx = next.firstIndex(of: .back), let legsIdx = next.firstIndex(of: .legs) {
            XCTAssertLessThan(backIdx, legsIdx) // back(100h) は legs(80h) より優先
        } else {
            XCTFail("back/legs が候補に含まれていない")
        }
    }
}
