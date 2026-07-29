import Foundation
import SwiftData

/// Supabase auth user に 1:1（§4.1）。ローカルではモック認証で生成される。
@Model
final class Profile {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var avatarURL: String?
    var bio: String?
    /// プッシュ通知の種類別 ON/OFF（サーバー側 send-push が参照）。既定 ON。
    var notifyLikes: Bool = true
    var notifyComments: Bool = true
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        avatarURL: String? = nil,
        bio: String? = nil,
        notifyLikes: Bool = true,
        notifyComments: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.bio = bio
        self.notifyLikes = notifyLikes
        self.notifyComments = notifyComments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
