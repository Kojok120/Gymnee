import XCTest
@testable import Gymnee

/// 「よくやる種目」ランキング（直近60日の使用回数トップ10）のテスト。
final class FrequentExerciseRankerTests: XCTestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-07-11T12:00:00Z")!
    private func daysAgo(_ d: Int) -> Date { now.addingTimeInterval(-Double(d) * 86_400) }

    private let bench = UUID()
    private let squat = UUID()
    private let dead = UUID()
    private let curl = UUID()

    func testRanksByCountThenRecency() {
        let usage: [UUID: [Date]] = [
            bench: [daysAgo(1), daysAgo(5), daysAgo(10)],        // 3回
            squat: [daysAgo(2), daysAgo(9)],                     // 2回・最終2日前
            dead: [daysAgo(3), daysAgo(4)],                      // 2回・最終3日前
            curl: [daysAgo(30)],                                 // 1回
        ]
        XCTAssertEqual(FrequentExerciseRanker.rank(usage: usage, asOf: now), [bench, squat, dead, curl])
    }

    func testOldUsageOutsideWindowIsIgnored() {
        // 61日前より古い使用は数えない。期間内使用が無い種目は対象外。
        let usage: [UUID: [Date]] = [
            bench: [daysAgo(1)],
            squat: [daysAgo(2)],
            dead: [daysAgo(61), daysAgo(90)],   // 全部期間外 → 対象外
            curl: [daysAgo(59), daysAgo(70)],   // 期間内1回だけ数える
        ]
        let ranked = FrequentExerciseRanker.rank(usage: usage, asOf: now)
        XCTAssertEqual(Set(ranked), Set([bench, squat, curl]))
        XCTAssertFalse(ranked.contains(dead))
    }

    func testHiddenWhenFewerThanThreeExercises() {
        // 対象種目が3未満ならセクション非表示（空を返す）。
        let usage: [UUID: [Date]] = [bench: [daysAgo(1)], squat: [daysAgo(2)]]
        XCTAssertEqual(FrequentExerciseRanker.rank(usage: usage, asOf: now), [])
    }

    func testLimitsToTopTen() {
        var usage: [UUID: [Date]] = [:]
        for i in 0..<15 {
            // 回数を 15,14,…,1 と変えて順位を確定させる。
            usage[UUID()] = (0...(14 - i)).map { _ in daysAgo(i + 1) }
        }
        XCTAssertEqual(FrequentExerciseRanker.rank(usage: usage, asOf: now).count, 10)
    }
}
