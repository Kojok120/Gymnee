import XCTest
@testable import Gymnee

/// コーチとの会話の「今日ぶん / それ以前」の切り分け。
/// 開くたびに過去の壁を見せないための境界が要件。
final class CoachTranscriptTests: XCTestCase {

    private struct Line {
        let at: Date
    }

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// 今日の 0 時が境界。前日 23:59 は past、今日 0:00 は today。
    func testSplitsAtStartOfToday() {
        let now = date(2026, 8, 11, 16, 15)
        let messages = [
            Line(at: date(2026, 8, 10, 23, 59)),
            Line(at: date(2026, 8, 11, 0, 0)),
            Line(at: date(2026, 8, 11, 16, 14)),
        ]
        let split = CoachTranscript.split(messages, now: now, calendar: calendar) { $0.at }
        XCTAssertEqual(split.past.count, 1)
        XCTAssertEqual(split.today.count, 2)
        XCTAssertEqual(split.past.first?.at, date(2026, 8, 10, 23, 59))
    }

    /// 今日まだ話していなければ today は空（空状態＝入り口の質問を出す）。
    func testTodayIsEmptyWhenNothingToday() {
        let now = date(2026, 8, 11, 9, 0)
        let messages = [Line(at: date(2026, 8, 9, 12, 0)), Line(at: date(2026, 8, 10, 12, 0))]
        let split = CoachTranscript.split(messages, now: now, calendar: calendar) { $0.at }
        XCTAssertEqual(split.past.count, 2)
        XCTAssertTrue(split.today.isEmpty)
    }

    /// 初回は両方空（過去への入口も出さない）。
    func testEmptyTranscript() {
        let split = CoachTranscript.split([Line](), now: date(2026, 8, 11, 9, 0), calendar: calendar) { $0.at }
        XCTAssertTrue(split.past.isEmpty)
        XCTAssertTrue(split.today.isEmpty)
    }

    /// 並び順は入力（時系列昇順）のまま保つ。
    func testPreservesOrder() {
        let now = date(2026, 8, 11, 20, 0)
        let messages = [
            Line(at: date(2026, 8, 11, 9, 0)),
            Line(at: date(2026, 8, 11, 12, 0)),
            Line(at: date(2026, 8, 11, 19, 0)),
        ]
        let split = CoachTranscript.split(messages, now: now, calendar: calendar) { $0.at }
        XCTAssertEqual(split.today.map(\.at), messages.map(\.at))
    }
}
