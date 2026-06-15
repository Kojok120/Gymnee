import XCTest
@testable import Gymnee

/// 連続記録・週次ゴール算出（§6.2）のテスト。
final class StreakCalculatorTests: XCTestCase {

    private var cal = Calendar(identifier: .gregorian)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return cal.date(from: c)!
    }

    func testCurrentStreakCountingFromToday() {
        let today = day(2026, 6, 15)
        let visits = [day(2026, 6, 15), day(2026, 6, 14), day(2026, 6, 13)]
        XCTAssertEqual(StreakCalculator.currentStreak(visitDays: visits, asOf: today, calendar: cal), 3)
    }

    func testCurrentStreakCountingFromYesterdayWhenTodayMissing() {
        let today = day(2026, 6, 15)
        // 今日は未来店だが昨日・一昨日に来店 → 連続は生きている（2）。
        let visits = [day(2026, 6, 14), day(2026, 6, 13)]
        XCTAssertEqual(StreakCalculator.currentStreak(visitDays: visits, asOf: today, calendar: cal), 2)
    }

    func testCurrentStreakBrokenWhenGapBeforeYesterday() {
        let today = day(2026, 6, 15)
        // 直近が3日前 → 連続は途切れている（0）。
        let visits = [day(2026, 6, 12), day(2026, 6, 11)]
        XCTAssertEqual(StreakCalculator.currentStreak(visitDays: visits, asOf: today, calendar: cal), 0)
    }

    func testCurrentStreakIgnoresDuplicateSameDay() {
        let today = day(2026, 6, 15)
        let visits = [day(2026, 6, 15), day(2026, 6, 15), day(2026, 6, 14)]
        XCTAssertEqual(StreakCalculator.currentStreak(visitDays: visits, asOf: today, calendar: cal), 2)
    }

    func testCurrentStreakEmpty() {
        XCTAssertEqual(StreakCalculator.currentStreak(visitDays: [], asOf: day(2026, 6, 15), calendar: cal), 0)
    }

    func testLongestStreak() {
        // 6/1-6/3 (3連続), 6/10-6/14 (5連続) → 最長 5。
        let visits = [
            day(2026, 6, 1), day(2026, 6, 2), day(2026, 6, 3),
            day(2026, 6, 10), day(2026, 6, 11), day(2026, 6, 12), day(2026, 6, 13), day(2026, 6, 14),
        ]
        XCTAssertEqual(StreakCalculator.longestStreak(visitDays: visits, calendar: cal), 5)
    }

    func testWeeklyVisitDaysDistinct() {
        // 2026-06-15 は月曜。週の範囲内に複数来店、同日複数は1日。
        var c = cal
        c.firstWeekday = 2 // 月曜始まり
        let ref = day(2026, 6, 17)
        let visits = [day(2026, 6, 15), day(2026, 6, 15), day(2026, 6, 17), day(2026, 6, 9)]
        XCTAssertEqual(StreakCalculator.weeklyVisitDays(visitDays: visits, in: ref, calendar: c), 2)
    }

    func testWeeklyAchievementRate() {
        var c = cal
        c.firstWeekday = 2
        let ref = day(2026, 6, 17)
        let visits = [day(2026, 6, 15), day(2026, 6, 16), day(2026, 6, 17)]
        XCTAssertEqual(StreakCalculator.weeklyAchievementRate(visitDays: visits, goal: 3, in: ref, calendar: c), 1.0, accuracy: 0.0001)
        XCTAssertEqual(StreakCalculator.weeklyAchievementRate(visitDays: visits, goal: 6, in: ref, calendar: c), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StreakCalculator.weeklyAchievementRate(visitDays: visits, goal: 0, in: ref, calendar: c), 0.0, accuracy: 0.0001)
    }
}
