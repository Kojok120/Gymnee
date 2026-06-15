import Foundation
import SwiftData

/// フォロー関係（§4.4）。ローカルでは UUID 参照（実マルチユーザは Supabase 接続後）。
@Model
final class Follow {
    @Attribute(.unique) var id: UUID
    var followerId: UUID
    var followeeId: UUID
    var followeeDisplayName: String?
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        followerId: UUID,
        followeeId: UUID,
        followeeDisplayName: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.followerId = followerId
        self.followeeId = followeeId
        self.followeeDisplayName = followeeDisplayName
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
        self.visibilityRaw = visibility.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
