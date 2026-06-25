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
    var notifyFriendCheckin: Bool = true
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
        notifyFriendCheckin: Bool = true,
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
        self.notifyFriendCheckin = notifyFriendCheckin
        self.notifyComments = notifyComments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// ジムマスタ（§4.1）。プリセット＋ユーザー作成の両方。来店から参照される。
@Model
final class Gym {
    @Attribute(.unique) var id: UUID
    var name: String
    var chain: String?
    var address: String?
    var lat: Double?
    var lng: Double?
    var sourceRaw: String
    var createdBy: UUID?
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool

    @Relationship(deleteRule: .cascade, inverse: \GymEquipment.gym)
    var equipment: [GymEquipment] = []

    @Relationship(deleteRule: .nullify, inverse: \Visit.gym)
    var visits: [Visit] = []

    var source: GymSource {
        get { GymSource(rawValue: sourceRaw) ?? .user }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        chain: String? = nil,
        address: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        source: GymSource = .user,
        createdBy: UUID? = nil,
        isFavorite: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.name = name
        self.chain = chain
        self.address = address
        self.lat = lat
        self.lng = lng
        self.sourceRaw = source.rawValue
        self.createdBy = createdBy
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// ジム別の設備メモ（§4.1・任意、将来コミュニティ化余地）。
@Model
final class GymEquipment {
    @Attribute(.unique) var id: UUID
    var label: String
    var note: String?
    var updatedAt: Date
    var isDirty: Bool

    var gym: Gym?

    init(
        id: UUID = UUID(),
        label: String,
        note: String? = nil,
        gym: Gym? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.label = label
        self.note = note
        self.gym = gym
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
