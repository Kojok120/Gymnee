import Foundation

/// SwiftData モデル（PostReaction / Comment）⇄ ドメイン値型（SocialActivity）の橋渡し。
/// 純粋ドメイン（`SocialActivityBuilder`）を SwiftData 非依存に保ちつつ、
/// アイコンのバッジ・ベルのバッジ・通知一覧の 3 箇所で同じ組み立てを共有する。
extension SocialActivity {
    init(reaction r: PostReaction) {
        self.init(id: r.id, postId: r.feedItemId, actorId: r.userId, date: r.createdAt,
                  kind: .reaction(r.kind), commentText: nil)
    }
    init(comment c: Comment) {
        self.init(id: c.id, postId: c.feedItemId, actorId: c.userId, date: c.createdAt,
                  kind: .comment, commentText: c.text)
    }
}

enum SocialActivityFeed {
    /// 自分の投稿に付いた他者の反応/コメントを新しい順で組み立てる（モデル配列入力）。
    static func build(
        reactions: [PostReaction],
        comments: [Comment],
        myPostIds: Set<UUID>,
        currentUserId: UUID,
        blockedIds: Set<UUID>
    ) -> [SocialActivity] {
        let merged = reactions.map(SocialActivity.init(reaction:)) + comments.map(SocialActivity.init(comment:))
        return SocialActivityBuilder.build(myPostIds: myPostIds, activities: merged,
                                           currentUserId: currentUserId, blockedIds: blockedIds)
    }

    /// 未読件数のショートカット（バッジ用）。lastSeen は timeIntervalSince1970。
    static func unreadCount(
        reactions: [PostReaction],
        comments: [Comment],
        myPostIds: Set<UUID>,
        currentUserId: UUID,
        blockedIds: Set<UUID>,
        lastSeen: Double
    ) -> Int {
        let activities = build(reactions: reactions, comments: comments, myPostIds: myPostIds,
                               currentUserId: currentUserId, blockedIds: blockedIds)
        return SocialActivityBuilder.unreadCount(activities, since: Date(timeIntervalSince1970: lastSeen))
    }
}
