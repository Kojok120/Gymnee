import Foundation
import SwiftData

/// ルーティン/テンプレ（§4.2）。
@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var name: String
    var note: String?
    var updatedAt: Date
    var isDirty: Bool

    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    var routineExercises: [RoutineExercise] = []

    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        note: String? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.note = note
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// テンプレの構成（§4.2）。
@Model
final class RoutineExercise {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var targetSets: Int
    var targetReps: Int?
    /// 種目別のレスト秒数（nil は既定値を使用）。
    var restSeconds: Int?
    var updatedAt: Date
    var isDirty: Bool

    var routine: Routine?
    var exercise: Exercise?

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        targetSets: Int = 3,
        targetReps: Int? = nil,
        restSeconds: Int? = nil,
        routine: Routine? = nil,
        exercise: Exercise? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.restSeconds = restSeconds
        self.routine = routine
        self.exercise = exercise
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

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
