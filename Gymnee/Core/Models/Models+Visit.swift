import Foundation
import SwiftData

/// 写真チェックインの本体（§4.2）。1 来店 = 1 レコード。
/// ジムは「来店の属性」として扱われ、ジムを跨いでも visits の連続性が保たれる（差別化の中核）。
@Model
final class Visit {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var visitedAt: Date
    var photoURL: String?
    /// ローカル保存した写真ファイル名（Documents 配下）。同期前のオフライン写真用。
    var localPhotoFilename: String?
    var lat: Double?
    var lng: Double?
    var note: String?
    var updatedAt: Date
    var isDirty: Bool

    var gym: Gym?

    @Relationship(deleteRule: .cascade, inverse: \VisitPartner.visit)
    var partners: [VisitPartner] = []

    @Relationship(deleteRule: .nullify, inverse: \Workout.visit)
    var workouts: [Workout] = []

    init(
        id: UUID = UUID(),
        userId: UUID,
        visitedAt: Date = .now,
        gym: Gym? = nil,
        photoURL: String? = nil,
        localPhotoFilename: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        note: String? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.visitedAt = visitedAt
        self.gym = gym
        self.photoURL = photoURL
        self.localPhotoFilename = localPhotoFilename
        self.lat = lat
        self.lng = lng
        self.note = note
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// 合トレタグ付け（§4.2）。双方の来店として表示する根拠。
/// partner はローカルではモックユーザー UUID（実マルチユーザは Supabase 接続後）。
@Model
final class VisitPartner {
    @Attribute(.unique) var id: UUID
    var partnerUserId: UUID
    var partnerDisplayName: String?
    var updatedAt: Date
    var isDirty: Bool

    var visit: Visit?

    init(
        id: UUID = UUID(),
        partnerUserId: UUID,
        partnerDisplayName: String? = nil,
        visit: Visit? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.partnerUserId = partnerUserId
        self.partnerDisplayName = partnerDisplayName
        self.visit = visit
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
