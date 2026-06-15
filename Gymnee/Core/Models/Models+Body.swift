import Foundation
import SwiftData

/// 体重・体脂肪・各部位サイズ（§4.3）。HealthKit と双方向（§6.9）。
@Model
final class BodyMetric {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var date: Date
    var weight: Double?
    var bodyFat: Double?
    /// 各部位サイズ（cm）。要件の measurements(jsonb) に対応。
    var measurements: [String: Double]
    /// HealthKit 由来かどうか（重複書き戻し防止）。
    var fromHealthKit: Bool
    var updatedAt: Date
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        userId: UUID,
        date: Date = .now,
        weight: Double? = nil,
        bodyFat: Double? = nil,
        measurements: [String: Double] = [:],
        fromHealthKit: Bool = false,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.date = date
        self.weight = weight
        self.bodyFat = bodyFat
        self.measurements = measurements
        self.fromHealthKit = fromHealthKit
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// 体型写真（§4.3）。来店写真と別枠・既定 private・月次比較（§6.7）。
@Model
final class ProgressPhoto {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var date: Date
    var photoURL: String?
    var localPhotoFilename: String?
    var visibilityRaw: String
    var note: String?
    var updatedAt: Date
    var isDirty: Bool

    var visibility: Visibility {
        get { Visibility(rawValue: visibilityRaw) ?? .private }
        set { visibilityRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        date: Date = .now,
        photoURL: String? = nil,
        localPhotoFilename: String? = nil,
        visibility: Visibility = .private,
        note: String? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.date = date
        self.photoURL = photoURL
        self.localPhotoFilename = localPhotoFilename
        self.visibilityRaw = visibility.rawValue
        self.note = note
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
