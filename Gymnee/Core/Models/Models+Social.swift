import Foundation
import SwiftData

/// フォロー関係（§4.4）。ローカルでは UUID 参照（実マルチユーザは Supabase 接続後）。
@Model
final class Follow {
    @Attribute(.unique) var id: UUID
    var followerId: UUID
    var followeeId: UUID
    var followeeDisplayName: String?
    /// このフレンド(followee)のチェックイン通知を受け取るか。フォロワー側の設定。
    var notify: Bool
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        followerId: UUID,
        followeeId: UUID,
        followeeDisplayName: String? = nil,
        notify: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.followerId = followerId
        self.followeeId = followeeId
        self.followeeDisplayName = followeeDisplayName
        self.notify = notify
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// ブロック関係（UGC安全 / App Store ガイドライン1.2.5）。
/// blocker が blocked を非表示にし、フォロー関係を双方向で遮断する。クライアントで一覧/検索から除外。
@Model
final class Block {
    @Attribute(.unique) var id: UUID
    var blockerId: UUID
    var blockedId: UUID
    var blockedDisplayName: String?
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        blockerId: UUID,
        blockedId: UUID,
        blockedDisplayName: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.blockerId = blockerId
        self.blockedId = blockedId
        self.blockedDisplayName = blockedDisplayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// 通報（UGC安全 / App Store ガイドライン1.2.5）。
/// reporter が対象ユーザー/コンテンツを理由付きで通報し、サーバ `reports` に記録（運営が確認）。
@Model
final class Report {
    @Attribute(.unique) var id: UUID
    var reporterId: UUID
    var reportedUserId: UUID
    /// 通報対象の種別（"user" / "feed_item" / "progress_photo" など）。
    var contextType: String?
    /// 対象コンテンツの id（ユーザー通報時は nil）。
    var contextId: UUID?
    var reason: String
    var detail: String?
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        reporterId: UUID,
        reportedUserId: UUID,
        contextType: String? = nil,
        contextId: UUID? = nil,
        reason: String,
        detail: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.reporterId = reporterId
        self.reportedUserId = reportedUserId
        self.contextType = contextType
        self.contextId = contextId
        self.reason = reason
        self.detail = detail
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// フィード生成元（§4.4）。type ＋ ref_id でソース実体を参照。
@Model
final class FeedItem {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var authorDisplayName: String?
    var typeRaw: String
    var refId: UUID
    var summary: String?
    /// 構造化スタッツ(JSON文字列)。ワークアウト投稿のみ。フォロワー側でリッチカードを描くため。
    var statsJSON: String?
    var visibilityRaw: String
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool

    var type: FeedItemType {
        get { FeedItemType(rawValue: typeRaw) ?? .visit }
        set { typeRaw = newValue.rawValue }
    }

    var visibility: Visibility {
        get { Visibility(rawValue: visibilityRaw) ?? .friends }
        set { visibilityRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        authorDisplayName: String? = nil,
        type: FeedItemType,
        refId: UUID,
        summary: String? = nil,
        statsJSON: String? = nil,
        visibility: Visibility = .friends,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.authorDisplayName = authorDisplayName
        self.typeRaw = type.rawValue
        self.refId = refId
        self.summary = summary
        self.statsJSON = statsJSON
        self.visibilityRaw = visibility.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// 投稿（feed_items）へのいいね/応援（§6.11）。1ユーザー1投稿1種別。
@Model
final class PostReaction {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var feedItemId: UUID
    var kindRaw: String
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool

    var kind: ReactionKind {
        get { ReactionKind(rawValue: kindRaw) ?? .like }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        feedItemId: UUID,
        kind: ReactionKind = .like,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.feedItemId = feedItemId
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// 投稿（feed_items）への公開コメント（③）。可視な投稿にのみ付き、参照可否は post_reactions と同条件。
/// 1対1の私信（DM）ではなく不特定/多数が読む「オープンな場」の投稿。author_display_name は profiles 未同期時の安全網。
@Model
final class Comment {
    @Attribute(.unique) var id: UUID
    var feedItemId: UUID
    var userId: UUID
    var authorDisplayName: String?
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        feedItemId: UUID,
        userId: UUID,
        authorDisplayName: String? = nil,
        text: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.feedItemId = feedItemId
        self.userId = userId
        self.authorDisplayName = authorDisplayName
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
