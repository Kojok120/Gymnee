import XCTest
@testable import Gymnee

/// ワークアウト総合時間の導出（WorkoutDuration）のテスト。
final class WorkoutDurationTests: XCTestCase {
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // MARK: - finalizedSeconds（完了時の確定）

    func testLiveSessionFinalizes() {
        // 18:00 開始 → 19:10 完了 = 70分をそのまま確定。
        let start = date(2026, 7, 5, 18, 0), end = date(2026, 7, 5, 19, 10)
        XCTAssertEqual(WorkoutDuration.finalizedSeconds(date: start, completedAt: end), 4200)
    }

    func testMidnightCrossingLiveSessionFinalizes() {
        // 23:30 開始 → 翌 0:30 完了 = 60分。日付をまたいでも経過が妥当なら確定。
        let start = date(2026, 7, 5, 23, 30), end = date(2026, 7, 6, 0, 30)
        XCTAssertEqual(WorkoutDuration.finalizedSeconds(date: start, completedAt: end), 3600)
    }

    func testPastDayBackfillNotFinalized() {
        // 過去日の後追い記録（date=前日の正午、完了=今）は経過が実時間でないため確定しない。
        let start = date(2026, 7, 4, 12, 0), end = date(2026, 7, 5, 20, 0)
        XCTAssertNil(WorkoutDuration.finalizedSeconds(date: start, completedAt: end))
    }

    func testTooLongElapsedNotFinalized() {
        // 上限（6時間）超えはライブ記録とみなさない。
        let start = date(2026, 7, 5, 12, 0), end = date(2026, 7, 5, 18, 1)
        XCTAssertNil(WorkoutDuration.finalizedSeconds(date: start, completedAt: end))
    }

    func testZeroOrNegativeElapsedNotFinalized() {
        let start = date(2026, 7, 5, 18, 0)
        XCTAssertNil(WorkoutDuration.finalizedSeconds(date: start, completedAt: start))
        XCTAssertNil(WorkoutDuration.finalizedSeconds(date: start, completedAt: date(2026, 7, 5, 17, 0)))
    }

    // MARK: - minutes（表示用導出）

    func testManualDurationWins() {
        // 手動/確定値がある場合は date/completedAt の経過より優先する。
        let start = date(2026, 7, 5, 18, 0), end = date(2026, 7, 5, 18, 3)
        XCTAssertEqual(WorkoutDuration.minutes(date: start, completedAt: end, durationSeconds: 3600), 60)
    }

    func testManualDurationClampsToOneMinute() {
        let start = date(2026, 7, 5, 18, 0)
        XCTAssertEqual(WorkoutDuration.minutes(date: start, completedAt: nil, durationSeconds: 30), 1)
    }

    func testLegacyDerivedFromElapsed() {
        // 旧データ（durationSeconds 無し）は妥当な経過から導出する。
        let start = date(2026, 7, 5, 18, 0), end = date(2026, 7, 5, 18, 45)
        XCTAssertEqual(WorkoutDuration.minutes(date: start, completedAt: end, durationSeconds: nil), 45)
    }

    func testLegacyPastDayBackfillIsNil() {
        // 旧データの後追い記録（経過が数時間〜数日）は極端な値を出さず未計測扱い。
        let start = date(2026, 7, 4, 12, 0), end = date(2026, 7, 5, 20, 0)
        XCTAssertNil(WorkoutDuration.minutes(date: start, completedAt: end, durationSeconds: nil))
    }

    func testIncompleteWorkoutIsNil() {
        XCTAssertNil(WorkoutDuration.minutes(date: date(2026, 7, 5, 18, 0), completedAt: nil, durationSeconds: nil))
    }
}
