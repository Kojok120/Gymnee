import XCTest
@testable import Gymnee

/// 自分の投稿への他者反応（通知）の集約・未読算出（§6.11）のテスト。
final class SocialActivityBuilderTests: XCTestCase {

    private let me = UUID()
    private let postA = UUID()
    private let postB = UUID()
    private let otherX = UUID()
    private let otherY = UUID()

    private func date(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    private func reaction(_ id: UUID = UUID(), post: UUID, actor: UUID, kind: ReactionKind = .like, at: TimeInterval) -> SocialActivity {
        SocialActivity(id: id, postId: post, actorId: actor, date: date(at), kind: .reaction(kind), commentText: nil)
    }
    private func comment(_ id: UUID = UUID(), post: UUID, actor: UUID, text: String, at: TimeInterval) -> SocialActivity {
        SocialActivity(id: id, postId: post, actorId: actor, date: date(at), kind: .comment, commentText: text)
    }

    // MARK: - build（フィルタ＋新しい順）

    func testBuildExcludesOwnAndForeignPostsAndBlocked() {
        let blocked = UUID()
        let input = [
            reaction(post: postA, actor: otherX, at: 100),     // ○ 自分の投稿への他者反応
            reaction(post: postA, actor: me, at: 110),         // × 自分の反応
            reaction(post: UUID(), actor: otherY, at: 120),    // × 自分の投稿ではない
            comment(post: postA, actor: blocked, text: "x", at: 130), // × ブロック相手
            comment(post: postB, actor: otherY, text: "ok", at: 140), // ○
        ]
        let out = SocialActivityBuilder.build(myPostIds: [postA, postB], activities: input,
                                              currentUserId: me, blockedIds: [blocked])
        XCTAssertEqual(out.count, 2)
        // 新しい順（140 → 100）
        XCTAssertEqual(out.map(\.date), [date(140), date(100)])
    }

    func testBuildSortsNewestFirst() {
        let input = [
            reaction(post: postA, actor: otherX, at: 100),
            reaction(post: postA, actor: otherY, at: 300),
            reaction(post: postA, actor: otherX, at: 200),
        ]
        let out = SocialActivityBuilder.build(myPostIds: [postA], activities: input, currentUserId: me, blockedIds: [])
        XCTAssertEqual(out.map(\.date), [date(300), date(200), date(100)])
    }

    // MARK: - group（投稿ごと集約）

    func testGroupAggregatesByPostNewestFirst() {
        let input = [
            comment(post: postA, actor: otherY, text: "nice", at: 500),   // postA 最新
            reaction(post: postA, actor: otherX, at: 400),
            reaction(post: postA, actor: otherX, at: 350),                // 同一 actor 重複
            reaction(post: postB, actor: otherY, at: 300),
        ]
        let sorted = SocialActivityBuilder.build(myPostIds: [postA, postB], activities: input, currentUserId: me, blockedIds: [])
        let groups = SocialActivityBuilder.group(sorted)

        XCTAssertEqual(groups.count, 2)
        // グループは最新日時で降順 → postA(500) が先
        XCTAssertEqual(groups[0].postId, postA)
        XCTAssertEqual(groups[0].latestDate, date(500))
        XCTAssertEqual(groups[0].reactionCount, 2)
        XCTAssertEqual(groups[0].commentCount, 1)
        XCTAssertEqual(groups[0].latestCommentText, "nice")
        // actorIds は重複排除・新しい順（otherY が最新コメント、次に otherX）
        XCTAssertEqual(groups[0].actorIds, [otherY, otherX])

        XCTAssertEqual(groups[1].postId, postB)
        XCTAssertEqual(groups[1].reactionCount, 1)
        XCTAssertEqual(groups[1].commentCount, 0)
        XCTAssertNil(groups[1].latestCommentText)
    }

    // MARK: - unreadCount（lastSeen 境界）

    func testUnreadCountCountsOnlyAfterLastSeen() {
        let activities = [
            reaction(post: postA, actor: otherX, at: 100),
            reaction(post: postA, actor: otherY, at: 200),
            comment(post: postA, actor: otherX, text: "y", at: 300),
        ]
        // 150 より後 = 200, 300 の 2 件
        XCTAssertEqual(SocialActivityBuilder.unreadCount(activities, since: date(150)), 2)
        // 全件より後 = 0（境界は厳密に > 。同値は既読）
        XCTAssertEqual(SocialActivityBuilder.unreadCount(activities, since: date(300)), 0)
        // epoch 起点 = 全件未読
        XCTAssertEqual(SocialActivityBuilder.unreadCount(activities, since: date(0)), 3)
    }
}
