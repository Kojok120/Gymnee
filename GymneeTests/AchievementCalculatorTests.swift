import XCTest
@testable import Gymnee

/// 実績バッジ算出のテスト。
final class AchievementCalculatorTests: XCTestCase {

    private func status(_ kind: AchievementCalculator.Kind, in statuses: [AchievementCalculator.Status]) -> AchievementCalculator.Status? {
        statuses.first { $0.kind == kind }
    }

    func testNothingEarnedAtZero() {
        let s = AchievementCalculator.statuses(totalVolumeKg: 0, workoutCount: 0, prCount: 0, visitCount: 0, longestWeeklyStreakWeeks: 0)
        for st in s {
            XCTAssertTrue(st.earnedLabels.isEmpty)
            XCTAssertNotNil(st.nextLabel)
            XCTAssertEqual(st.progressToNext, 0, accuracy: 0.0001)
        }
    }

    func testVolumeTiersAndProgress() {
        // 30t: 10t 達成済み、次は 50t。進捗 = (30-10)/(50-10) = 0.5
        let s = AchievementCalculator.statuses(totalVolumeKg: 30_000, workoutCount: 0, prCount: 0, visitCount: 0, longestWeeklyStreakWeeks: 0)
        let v = status(.volume, in: s)!
        XCTAssertEqual(v.earnedLabels, ["10t"])
        XCTAssertEqual(v.nextLabel, "50t")
        XCTAssertEqual(v.progressToNext, 0.5, accuracy: 0.0001)
    }

    func testExactThresholdCountsAsEarned() {
        let s = AchievementCalculator.statuses(totalVolumeKg: 0, workoutCount: 10, prCount: 0, visitCount: 0, longestWeeklyStreakWeeks: 0)
        XCTAssertEqual(status(.workouts, in: s)?.earnedLabels, ["10回"])
    }

    func testAllTiersEarned() {
        let s = AchievementCalculator.statuses(totalVolumeKg: 2_000_000, workoutCount: 0, prCount: 0, visitCount: 0, longestWeeklyStreakWeeks: 0)
        let v = status(.volume, in: s)!
        XCTAssertEqual(v.earnedLabels.count, AchievementCalculator.volumeTiersKg.count)
        XCTAssertNil(v.nextLabel)
        XCTAssertEqual(v.progressToNext, 1)
    }

    func testWeeklyStreakLabels() {
        let s = AchievementCalculator.statuses(totalVolumeKg: 0, workoutCount: 0, prCount: 0, visitCount: 0, longestWeeklyStreakWeeks: 12)
        XCTAssertEqual(status(.weeklyStreak, in: s)?.earnedLabels, ["4週", "12週"])
        XCTAssertEqual(status(.weeklyStreak, in: s)?.nextLabel, "26週")
    }

    func testNonFiniteVolumeIsSafe() {
        let s = AchievementCalculator.statuses(totalVolumeKg: .nan, workoutCount: 0, prCount: 0, visitCount: 0, longestWeeklyStreakWeeks: 0)
        XCTAssertEqual(status(.volume, in: s)?.earnedLabels, [])
    }
}
