import Foundation

/// 自分の投稿に付いた他者の反応（いいね/応援/コメント）= ソーシャル通知の 1 件。
/// SwiftData 非依存の値型にして純粋関数でテストできるようにする（呼び出し側でモデルから射影する）。
struct SocialActivity: Identifiable, Equatable {
    enum Kind: Equatable {
        case reaction(ReactionKind)
        case comment
    }
    /// 反応/コメント行の一意キー（PostReaction.id / Comment.id）。
    let id: UUID
    /// 対象 feed_item（= 自分の投稿）の id。
    let postId: UUID
    /// 反応した相手の userId。
    let actorId: UUID
    let date: Date
    let kind: Kind
    /// コメントのとき本文（リアクションは nil）。
    let commentText: String?
}

/// 投稿ごとに集約した通知の 1 グループ（一覧の 1 行）。
struct SocialActivityGroup: Identifiable, Equatable {
    let postId: UUID
    /// このグループ内で最も新しい反応/コメントの日時（並び順・未読判定に使う）。
    let latestDate: Date
    /// 反応した相手（重複排除・新しい順）。表示名解決は呼び出し側が行う。
    let actorIds: [UUID]
    let reactionCount: Int
    let commentCount: Int
    /// 最新のコメント本文（プレビュー用。コメントが無ければ nil）。
    let latestCommentText: String?
    var id: UUID { postId }
}

/// ソーシャル通知（自分の投稿への他者反応）の純粋ロジック。
/// アイコンのバッジ・ベルのバッジ・通知一覧の 3 箇所で共有する（安定ドメインルール＝DRY 対象）。
enum SocialActivityBuilder {
    /// 「最後に通知一覧を見た時刻」を保持する UserDefaults / @AppStorage キー（timeIntervalSince1970）。
    static let lastSeenDefaultsKey = "gymnee.social.lastSeenActivityAt"

    /// 自分の投稿に付いた「他者」の反応/コメントだけを新しい順に束ねる。
    /// 自分自身の反応・ブロック相手・自分の投稿以外への反応は除外する。
    static func build(
        myPostIds: Set<UUID>,
        activities: [SocialActivity],
        currentUserId: UUID,
        blockedIds: Set<UUID>
    ) -> [SocialActivity] {
        activities
            .filter { myPostIds.contains($0.postId) && $0.actorId != currentUserId && !blockedIds.contains($0.actorId) }
            .sorted { $0.date > $1.date }
    }

    /// 投稿ごとに集約する。入力は `build` の出力（新しい順）を想定し、各グループも最新日時で降順に並ぶ。
    static func group(_ activities: [SocialActivity]) -> [SocialActivityGroup] {
        var order: [UUID] = []
        var byPost: [UUID: [SocialActivity]] = [:]
        for a in activities {
            if byPost[a.postId] == nil { order.append(a.postId) }
            byPost[a.postId, default: []].append(a)
        }
        return order.map { pid in
            let items = byPost[pid] ?? []   // 新しい順を維持
            var seenActors = Set<UUID>()
            let actorIds = items.compactMap { seenActors.insert($0.actorId).inserted ? $0.actorId : nil }
            let reactionCount = items.reduce(0) { acc, a in
                if case .reaction = a.kind { return acc + 1 } else { return acc }
            }
            let latestComment = items.first { if case .comment = $0.kind { return true } else { return false } }
            return SocialActivityGroup(
                postId: pid,
                latestDate: items.first?.date ?? .distantPast,
                actorIds: actorIds,
                reactionCount: reactionCount,
                commentCount: items.count - reactionCount,
                latestCommentText: latestComment?.commentText
            )
        }
    }

    /// 未読件数（lastSeen より後に発生した個別イベント数）。バッジに表示する。
    static func unreadCount(_ activities: [SocialActivity], since lastSeen: Date) -> Int {
        activities.reduce(0) { $0 + ($1.date > lastSeen ? 1 : 0) }
    }
}
