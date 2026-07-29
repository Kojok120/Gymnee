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
        let days = [day(2026, 6, 15), day(2026, 6, 14), day(2026, 6, 13)]
        XCTAssertEqual(StreakCalculator.currentStreak(activeDays: days, asOf: today, calendar: cal), 3)
    }

    func testCurrentStreakCountingFromYesterdayWhenTodayMissing() {
        let today = day(2026, 6, 15)
        // 今日は未記録だが昨日・一昨日に記録 → 連続は生きている（2）。
        let days = [day(2026, 6, 14), day(2026, 6, 13)]
        XCTAssertEqual(StreakCalculator.currentStreak(activeDays: days, asOf: today, calendar: cal), 2)
    }

    func testCurrentStreakBrokenWhenGapBeforeYesterday() {
        let today = day(2026, 6, 15)
        // 直近が3日前 → 連続は途切れている（0）。
        let days = [day(2026, 6, 12), day(2026, 6, 11)]
        XCTAssertEqual(StreakCalculator.currentStreak(activeDays: days, asOf: today, calendar: cal), 0)
    }

    func testCurrentStreakIgnoresDuplicateSameDay() {
        let today = day(2026, 6, 15)
        let days = [day(2026, 6, 15), day(2026, 6, 15), day(2026, 6, 14)]
        XCTAssertEqual(StreakCalculator.currentStreak(activeDays: days, asOf: today, calendar: cal), 2)
    }

    func testCurrentStreakEmpty() {
        XCTAssertEqual(StreakCalculator.currentStreak(activeDays: [], asOf: day(2026, 6, 15), calendar: cal), 0)
    }

    func testLongestStreak() {
        // 6/1-6/3 (3連続), 6/10-6/14 (5連続) → 最長 5。
        let days = [
            day(2026, 6, 1), day(2026, 6, 2), day(2026, 6, 3),
            day(2026, 6, 10), day(2026, 6, 11), day(2026, 6, 12), day(2026, 6, 13), day(2026, 6, 14),
        ]
        XCTAssertEqual(StreakCalculator.longestStreak(activeDays: days, calendar: cal), 5)
    }

    func testWeeklyActiveDaysDistinct() {
        // 2026-06-15 は月曜。週の範囲内に複数記録、同日複数は1日。
        var c = cal
        c.firstWeekday = 2 // 月曜始まり
        let ref = day(2026, 6, 17)
        let days = [day(2026, 6, 15), day(2026, 6, 15), day(2026, 6, 17), day(2026, 6, 9)]
        XCTAssertEqual(StreakCalculator.weeklyActiveDays(activeDays: days, in: ref, calendar: c), 2)
    }

    // MARK: - 月次活動日数（投稿カードの「今月○日目」）

    func testMonthlyActiveDaysDistinct() {
        // 同日複数記録は 1 日。月内の distinct 日数を数える。
        let ref = day(2026, 6, 17)
        let days = [day(2026, 6, 1), day(2026, 6, 1), day(2026, 6, 15), day(2026, 6, 17)]
        XCTAssertEqual(StreakCalculator.monthlyActiveDays(activeDays: days, in: ref, calendar: cal), 3)
    }

    func testMonthlyActiveDaysExcludesOtherMonths() {
        // 前月末・翌月頭は数えない（月境界）。
        let ref = day(2026, 6, 17)
        let days = [day(2026, 5, 31), day(2026, 6, 1), day(2026, 6, 30), day(2026, 7, 1)]
        XCTAssertEqual(StreakCalculator.monthlyActiveDays(activeDays: days, in: ref, calendar: cal), 2)
    }

    func testMonthlyActiveDaysCountsFirstAndLastDayOfMonth() {
        // 月初 0:00 と月末 23:59 が取りこぼされないこと。
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 1; c.hour = 0; c.minute = 0
        let firstMoment = cal.date(from: c)!
        c.day = 30; c.hour = 23; c.minute = 59
        let lastMoment = cal.date(from: c)!
        XCTAssertEqual(
            StreakCalculator.monthlyActiveDays(activeDays: [firstMoment, lastMoment], in: day(2026, 6, 17), calendar: cal),
            2
        )
    }

    func testMonthlyActiveDaysEmpty() {
        XCTAssertEqual(StreakCalculator.monthlyActiveDays(activeDays: [], in: day(2026, 6, 17), calendar: cal), 0)
    }

    func testWeeklyAchievementRate() {
        var c = cal
        c.firstWeekday = 2
        let ref = day(2026, 6, 17)
        let days = [day(2026, 6, 15), day(2026, 6, 16), day(2026, 6, 17)]
        XCTAssertEqual(StreakCalculator.weeklyAchievementRate(activeDays: days, goal: 3, in: ref, calendar: c), 1.0, accuracy: 0.0001)
        XCTAssertEqual(StreakCalculator.weeklyAchievementRate(activeDays: days, goal: 6, in: ref, calendar: c), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StreakCalculator.weeklyAchievementRate(activeDays: days, goal: 0, in: ref, calendar: c), 0.0, accuracy: 0.0001)
    }

    // MARK: - 週次ストリーク（⑥）。6/15 は月曜（月曜始まりカレンダー）。

    private var weekCal: Calendar { var c = cal; c.firstWeekday = 2; return c }

    func testWeeklyStreakCountsConsecutiveMetWeeks() {
        // 今週・先週・先々週がすべて週3達成 → 3週連続（フリーズ無し）。
        let ref = day(2026, 6, 17)
        let days = [
            day(2026, 6, 15), day(2026, 6, 16), day(2026, 6, 17),  // 今週
            day(2026, 6, 8), day(2026, 6, 9), day(2026, 6, 10),    // 先週
            day(2026, 6, 1), day(2026, 6, 2), day(2026, 6, 3),     // 先々週
        ]
        let s = StreakCalculator.currentWeeklyStreak(activeDays: days, weeklyGoal: 3, asOf: ref, calendar: weekCal, freezesPerMonth: 0)
        XCTAssertEqual(s.weeks, 3)
        XCTAssertEqual(s.freezesUsed, 0)
        XCTAssertTrue(s.metThisWeek)
        XCTAssertEqual(s.activeDaysThisWeek, 3)
    }

    func testWeeklyStreakDoesNotPenalizeInProgressWeek() {
        // 今週はまだ1回（未達）でも、進行中とみなし途切れにしない → 先週からの2週。
        let ref = day(2026, 6, 17)
        let days = [
            day(2026, 6, 15),                                       // 今週（未達）
            day(2026, 6, 8), day(2026, 6, 9), day(2026, 6, 10),    // 先週
            day(2026, 6, 1), day(2026, 6, 2), day(2026, 6, 3),     // 先々週
        ]
        let s = StreakCalculator.currentWeeklyStreak(activeDays: days, weeklyGoal: 3, asOf: ref, calendar: weekCal, freezesPerMonth: 0)
        XCTAssertEqual(s.weeks, 2)
        XCTAssertFalse(s.metThisWeek)
        XCTAssertEqual(s.activeDaysThisWeek, 1)
    }

    func testWeeklyStreakFreezeAbsorbsOneGap() {
        // 先週だけ未達でも、フリーズ1で吸収して連続を継続。
        let ref = day(2026, 6, 17)
        let days = [
            day(2026, 6, 15), day(2026, 6, 16), day(2026, 6, 17),  // 今週 met
            day(2026, 6, 8),                                        // 先週 未達（gap）
            day(2026, 6, 1), day(2026, 6, 2), day(2026, 6, 3),     // 先々週 met
            day(2026, 5, 25), day(2026, 5, 26), day(2026, 5, 27),  // その前 met
        ]
        let s = StreakCalculator.currentWeeklyStreak(activeDays: days, weeklyGoal: 3, asOf: ref, calendar: weekCal, freezesPerMonth: 1)
        XCTAssertEqual(s.weeks, 3)
        XCTAssertEqual(s.freezesUsed, 1)
    }

    func testWeeklyStreakBreaksWhenGapExceedsFreeze() {
        // 連続2週の未達はフリーズ1では吸収しきれず途切れる。
        let ref = day(2026, 6, 17)
        let days = [
            day(2026, 6, 15), day(2026, 6, 16), day(2026, 6, 17),  // 今週 met
            day(2026, 6, 8),                                        // 先週 未達
            day(2026, 6, 1),                                        // 先々週 未達
            day(2026, 5, 25), day(2026, 5, 26), day(2026, 5, 27),  // met（届かない）
        ]
        let s = StreakCalculator.currentWeeklyStreak(activeDays: days, weeklyGoal: 3, asOf: ref, calendar: weekCal, freezesPerMonth: 1)
        XCTAssertEqual(s.weeks, 1)
        XCTAssertEqual(s.freezesUsed, 1)
    }

    func testWeeklyStreakFreezeIsPerMonth() {
        // 6月の未達1週・5月の未達1週は、それぞれ別の月のトークンで吸収できる → 連続継続。
        let ref = day(2026, 6, 17)
        let days = [
            day(2026, 6, 15), day(2026, 6, 16), day(2026, 6, 17),  // 6/15週 met（6月）
            day(2026, 6, 8),                                        // 6/8週 未達（6月・freeze）
            day(2026, 6, 1), day(2026, 6, 2), day(2026, 6, 3),     // 6/1週 met（6月）
            day(2026, 5, 25),                                       // 5/25週 未達（5月・freeze）
            day(2026, 5, 18), day(2026, 5, 19), day(2026, 5, 20),  // 5/18週 met（5月）
        ]
        let s = StreakCalculator.currentWeeklyStreak(activeDays: days, weeklyGoal: 3, asOf: ref, calendar: weekCal, freezesPerMonth: 1)
        XCTAssertEqual(s.weeks, 3)        // 達成週: 6/15・6/1・5/18
        XCTAssertEqual(s.freezesUsed, 2)  // 6月と5月で各1回
    }

    func testLongestWeeklyStreak() {
        // 3週連続達成 → gap → 1週達成。最長は3。
        let days = [
            day(2026, 6, 1), day(2026, 6, 2), day(2026, 6, 3),
            day(2026, 6, 8), day(2026, 6, 9), day(2026, 6, 10),
            day(2026, 6, 15), day(2026, 6, 16), day(2026, 6, 17),
            day(2026, 6, 22),                                       // gap 週（未達）
            day(2026, 6, 29), day(2026, 6, 30), day(2026, 7, 1),
        ]
        XCTAssertEqual(StreakCalculator.longestWeeklyStreak(activeDays: days, weeklyGoal: 3, calendar: weekCal), 3)
    }
}
