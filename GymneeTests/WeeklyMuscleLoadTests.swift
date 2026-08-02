import XCTest
@testable import Gymnee

/// 人体図の塗り（今週どれだけ鍛えたか）のテスト。
final class WeeklyMuscleLoadTests: XCTestCase {

    /// 2026-06-11(木) 21:00 JST。週(日曜始まり: 6/7〜6/13)の後半なので、
    /// 数日前の記録は同じ週・9日前の記録は先週になる。
    private let now = Date(timeIntervalSince1970: 1_781_179_200)

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        c.firstWeekday = 1
        return c
    }

    private func entry(_ muscle: MuscleGroup, daysAgo: Double, sets: Int) -> MuscleFatigue.SessionEntry {
        MuscleFatigue.SessionEntry(muscle: muscle, completedAt: now.addingTimeInterval(-daysAgo * 86400), setCount: sets)
    }

    private func status(_ muscle: MuscleGroup, in list: [WeeklyMuscleLoad.Status]) -> WeeklyMuscleLoad.Status {
        list.first { $0.muscle == muscle }!
    }

    // MARK: - 基本

    func testNoEntriesMeansEveryMuscleUntouched() {
        let list = WeeklyMuscleLoad.statuses(entries: [], asOf: now, calendar: calendar)
        XCTAssertEqual(list.count, RecoveryAnalyzer.trackedMuscles.count)
        for s in list {
            XCTAssertEqual(s.sets, 0)
            XCTAssertEqual(s.progress, 0, accuracy: 0.0001)
            XCTAssertTrue(s.isUntouched)
            XCTAssertFalse(s.isComplete)
        }
        XCTAssertEqual(WeeklyMuscleLoad.totalSets(list), 0)
        XCTAssertEqual(WeeklyMuscleLoad.untouched(list), RecoveryAnalyzer.trackedMuscles)
    }

    func testSessionsInTheSameWeekAreSummed() {
        // 疲労度と違い、週内の複数セッションは合算される（週の積み上げを見せるため）。
        let list = WeeklyMuscleLoad.statuses(
            entries: [entry(.chest, daysAgo: 0, sets: 4), entry(.chest, daysAgo: 2, sets: 5)],
            asOf: now, calendar: calendar
        )
        XCTAssertEqual(status(.chest, in: list).sets, 9)
    }

    func testProgressReachesOneAtTargetAndIsCapped() {
        let target = WeeklyMuscleLoad.targetSets(for: .chest)
        let atTarget = WeeklyMuscleLoad.statuses(entries: [entry(.chest, daysAgo: 0, sets: target)], asOf: now, calendar: calendar)
        XCTAssertEqual(status(.chest, in: atTarget).progress, 1.0, accuracy: 0.0001)
        XCTAssertTrue(status(.chest, in: atTarget).isComplete)

        // 目安を超えても 1.0 で頭打ち（塗りが飽和して差が読めなくなるのを防ぐ）。
        let over = WeeklyMuscleLoad.statuses(entries: [entry(.chest, daysAgo: 0, sets: target * 3)], asOf: now, calendar: calendar)
        XCTAssertEqual(status(.chest, in: over).progress, 1.0, accuracy: 0.0001)
    }

    func testPartialProgressIsProportional() {
        let target = WeeklyMuscleLoad.targetSets(for: .chest)
        let list = WeeklyMuscleLoad.statuses(entries: [entry(.chest, daysAgo: 1, sets: target / 2)], asOf: now, calendar: calendar)
        XCTAssertEqual(status(.chest, in: list).progress, 0.5, accuracy: 0.05)
        XCTAssertFalse(status(.chest, in: list).isUntouched)
        XCTAssertFalse(status(.chest, in: list).isComplete)
    }

    // MARK: - 週の境界

    func testPreviousWeekIsExcluded() {
        // 先週の記録が今週の塗りに残ると「今週の成果」が嘘になる。
        let list = WeeklyMuscleLoad.statuses(entries: [entry(.chest, daysAgo: 9, sets: 20)], asOf: now, calendar: calendar)
        XCTAssertEqual(status(.chest, in: list).sets, 0)
        XCTAssertTrue(status(.chest, in: list).isUntouched)
    }

    func testFutureEntriesAreIgnored() {
        // 時刻ズレ・手入力ミスで未来日になった記録は実績に数えない。
        let future = MuscleFatigue.SessionEntry(muscle: .back, completedAt: now.addingTimeInterval(3600), setCount: 10)
        let list = WeeklyMuscleLoad.statuses(entries: [future], asOf: now, calendar: calendar)
        XCTAssertEqual(status(.back, in: list).sets, 0)
    }

    // MARK: - 集計

    func testTotalAndUntouchedReflectOnlyTrackedMuscles() {
        let list = WeeklyMuscleLoad.statuses(
            entries: [entry(.chest, daysAgo: 0, sets: 3), entry(.legs, daysAgo: 1, sets: 6)],
            asOf: now, calendar: calendar
        )
        XCTAssertEqual(WeeklyMuscleLoad.totalSets(list), 9)
        let untouched = WeeklyMuscleLoad.untouched(list)
        XCTAssertFalse(untouched.contains(.chest))
        XCTAssertFalse(untouched.contains(.legs))
        XCTAssertEqual(untouched.count, RecoveryAnalyzer.trackedMuscles.count - 2)
    }

    func testEveryTrackedMuscleHasAPositiveTarget() {
        // 目安が 0 の部位があると progress がゼロ除算相当になり、永久に塗られない。
        for muscle in RecoveryAnalyzer.trackedMuscles {
            XCTAssertGreaterThan(WeeklyMuscleLoad.targetSets(for: muscle), 0, "\(muscle.rawValue) の目安セット数が 0")
        }
    }
}
