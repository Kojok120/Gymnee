import XCTest
@testable import Gymnee

final class ReengagementReminderTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return value
    }

    private func date(_ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    func testNoReminderWithoutCompletedWorkout() {
        XCTAssertTrue(ReengagementReminder.scheduledDates(lastCompletedAt: nil, now: date(18, hour: 12), calendar: calendar).isEmpty)
    }

    func testSchedulesFromThirdDayAfterLastWorkout() {
        let dates = ReengagementReminder.scheduledDates(
            lastCompletedAt: date(15, hour: 20), now: date(16, hour: 12), calendar: calendar
        )
        XCTAssertEqual(dates, [date(18, hour: 19), date(19, hour: 19), date(20, hour: 19)])
    }

    func testSchedulesTodayWhenReminderTimeHasNotPassed() {
        let dates = ReengagementReminder.scheduledDates(
            lastCompletedAt: date(15, hour: 20), now: date(18, hour: 12), calendar: calendar
        )
        XCTAssertEqual(dates.first, date(18, hour: 19))
    }

    func testMovesToTomorrowWhenTodayReminderTimeHasPassed() {
        let dates = ReengagementReminder.scheduledDates(
            lastCompletedAt: date(15, hour: 20), now: date(18, hour: 20), calendar: calendar
        )
        XCTAssertEqual(dates, [date(19, hour: 19), date(20, hour: 19), date(21, hour: 19)])
    }
}
