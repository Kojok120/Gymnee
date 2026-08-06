import Foundation
import SwiftData

/// PR（§4.2）。検出時に記録／更新（§6.5）。
@Model
final class PersonalRecord {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var typeRaw: String
    var value: Double
    var achievedAt: Date
    var workoutId: UUID?
    var updatedAt: Date
    var isDirty: Bool

    var exercise: Exercise?

    var type: PRType {
        get { PRType(rawValue: typeRaw) ?? .maxWeight }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        type: PRType,
        value: Double,
        achievedAt: Date = .now,
        workoutId: UUID? = nil,
        exercise: Exercise? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.typeRaw = type.rawValue
        self.value = value
        self.achievedAt = achievedAt
        self.workoutId = workoutId
        self.exercise = exercise
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
