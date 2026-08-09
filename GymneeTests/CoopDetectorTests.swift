import XCTest
@testable import Gymnee

/// 合トレ（同じ日に仲間も記録した）判定のテスト。
final class CoopDetectorTests: XCTestCase {

    private let today = Date(timeIntervalSince1970: 1_700_000_000)

    private func item(_ name: String?, userId: UUID = UUID(), daysAgo: Int = 0, type: FeedItemType = .workout) -> FeedItem {
        FeedItem(
            userId: userId,
            authorDisplayName: name,
            type: type,
            refId: UUID(),
            createdAt: today.addingTimeInterval(Double(-daysAgo) * 86_400)
        )
    }

    func testNoPartnersWithoutPosts() {
        XCTAssertTrue(CoopDetector.partnersToday(feedItems: [], asOf: today).isEmpty)
    }

    func testPicksUpTodaysWorkoutPosts() {
        let partners = CoopDetector.partnersToday(feedItems: [item("ゆうき")], asOf: today)
        XCTAssertEqual(partners, ["ゆうき"])
    }

    func testIgnoresOtherDays() {
        let partners = CoopDetector.partnersToday(feedItems: [item("ゆうき", daysAgo: 1)], asOf: today)
        XCTAssertTrue(partners.isEmpty, "昨日の記録は合トレにしない")
    }

    func testIgnoresNonWorkoutPosts() {
        let partners = CoopDetector.partnersToday(feedItems: [item("ゆうき", type: .pr)], asOf: today)
        XCTAssertTrue(partners.isEmpty, "PR 投稿だけでは同じ日にジムに行った証拠にならない")
    }

    func testDeduplicatesSameUser() {
        let uid = UUID()
        let partners = CoopDetector.partnersToday(
            feedItems: [item("ゆうき", userId: uid), item("ゆうき", userId: uid)], asOf: today
        )
        XCTAssertEqual(partners.count, 1)
    }

    func testFallsBackWhenNameMissing() {
        XCTAssertEqual(CoopDetector.partnersToday(feedItems: [item(nil)], asOf: today), ["仲間"])
        XCTAssertEqual(CoopDetector.partnersToday(feedItems: [item("  ")], asOf: today), ["仲間"])
    }

    func testCapsAtFiveNames() {
        let items = (0..<9).map { item("ユーザー\($0)") }
        XCTAssertEqual(CoopDetector.partnersToday(feedItems: items, asOf: today).count, 5)
    }
}
