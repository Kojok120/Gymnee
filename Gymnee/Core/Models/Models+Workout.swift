import Foundation
import SwiftData

/// セッション（§4.2）。来店に紐付くが、ジム外記録も許容（visit は nullable）。
@Model
final class Workout {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var date: Date
    var name: String
    /// テンプレ参照（§4.2 routine_id nullable）。軽量参照のため UUID で保持。
    var routineId: UUID?
    var note: String?
    /// 予定→実績（§6.2）。未来日に計画したワークアウトかどうか、消化済みか。
    var isPlanned: Bool
    var completedAt: Date?
    var updatedAt: Date
    var isDirty: Bool

    var visit: Visit?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    var exercises: [WorkoutExercise] = []

    init(
        id: UUID = UUID(),
        userId: UUID,
        date: Date = .now,
        name: String = "ワークアウト",
        routineId: UUID? = nil,
        note: String? = nil,
        isPlanned: Bool = false,
        completedAt: Date? = nil,
        visit: Visit? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.date = date
        self.name = name
        self.routineId = routineId
        self.note = note
        self.isPlanned = isPlanned
        self.completedAt = completedAt
        self.visit = visit
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// 種目マスタ（§4.2）。プリセット＋ユーザー作成。
@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var muscleGroupRaw: String
    var equipmentRaw: String
    var isCustom: Bool
    var createdBy: UUID?
    var updatedAt: Date
    var isDirty: Bool

    @Relationship(deleteRule: .nullify, inverse: \WorkoutExercise.exercise)
    var workoutExercises: [WorkoutExercise] = []

    @Relationship(deleteRule: .nullify, inverse: \RoutineExercise.exercise)
    var routineExercises: [RoutineExercise] = []

    @Relationship(deleteRule: .cascade, inverse: \PersonalRecord.exercise)
    var personalRecords: [PersonalRecord] = []

    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .fullBody }
        set { muscleGroupRaw = newValue.rawValue }
    }

    var equipment: EquipmentType {
        get { EquipmentType(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        muscleGroup: MuscleGroup,
        equipment: EquipmentType,
        isCustom: Bool = false,
        createdBy: UUID? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.equipmentRaw = equipment.rawValue
        self.isCustom = isCustom
        self.createdBy = createdBy
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// セッション内の種目並び（§4.2）。
@Model
final class WorkoutExercise {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var note: String?
    /// スーパーセットのグループ識別子。同じ値同士が 1 つのスーパーセット（nil は単独）。
    var supersetGroup: Int?
    var updatedAt: Date
    var isDirty: Bool

    var workout: Workout?
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.workoutExercise)
    var sets: [ExerciseSet] = []

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        note: String? = nil,
        supersetGroup: Int? = nil,
        workout: Workout? = nil,
        exercise: Exercise? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.note = note
        self.supersetGroup = supersetGroup
        self.workout = workout
        self.exercise = exercise
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// L3 の最小単位（§4.2）。追記型でコンフリクトを避ける（§7・§9-7）。
@Model
final class ExerciseSet {
    @Attribute(.unique) var id: UUID
    var setIndex: Int
    var weight: Double
    var reps: Int
    var rpe: Double?
    var rir: Int?
    var typeRaw: String
    var isPR: Bool
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool

    var workoutExercise: WorkoutExercise?

    var type: SetType {
        get { SetType(rawValue: typeRaw) ?? .normal }
        set { typeRaw = newValue.rawValue }
    }

    /// このセットのボリューム（重量 × レップ）。ウォームアップは集計から除外する想定。
    var volume: Double { weight * Double(reps) }

    init(
        id: UUID = UUID(),
        setIndex: Int,
        weight: Double = 0,
        reps: Int = 0,
        rpe: Double? = nil,
        rir: Int? = nil,
        type: SetType = .normal,
        isPR: Bool = false,
        isCompleted: Bool = false,
        workoutExercise: WorkoutExercise? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.rir = rir
        self.typeRaw = type.rawValue
        self.isPR = isPR
        self.isCompleted = isCompleted
        self.workoutExercise = workoutExercise
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
