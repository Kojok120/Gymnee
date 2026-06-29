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
    /// この種目の既定の重量の数え方（両側/片側）。
    var weightModeRaw: String = WeightMode.both.rawValue
    /// 計測タイプ（weight / bodyweight / time）。記録カードの形を決める。
    var measurementTypeRaw: String = MeasurementType.weight.rawValue
    /// 自重種目の荷重スタイル（自重のみ/荷重/補助）。bodyweight のときだけ意味を持つ。
    var loadModeRaw: String = LoadMode.none.rawValue
    var updatedAt: Date
    var isDirty: Bool

    var weightMode: WeightMode {
        get { WeightMode(rawValue: weightModeRaw) ?? .both }
        set { weightModeRaw = newValue.rawValue }
    }

    var measurementType: MeasurementType {
        get { MeasurementType(rawValue: measurementTypeRaw) ?? .weight }
        set { measurementTypeRaw = newValue.rawValue }
    }

    var loadMode: LoadMode {
        get { LoadMode(rawValue: loadModeRaw) ?? .none }
        set { loadModeRaw = newValue.rawValue }
    }

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
        weightMode: WeightMode = .both,
        measurementType: MeasurementType = .weight,
        loadMode: LoadMode = .none,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.equipmentRaw = equipment.rawValue
        self.isCustom = isCustom
        self.createdBy = createdBy
        self.weightModeRaw = weightMode.rawValue
        self.measurementTypeRaw = measurementType.rawValue
        self.loadModeRaw = loadMode.rawValue
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
    /// 種目別レスト秒数（nil は既定値）。記録UIでは未使用（計画/同期互換のため保持）。
    var restSeconds: Int?
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
        restSeconds: Int? = nil,
        workout: Workout? = nil,
        exercise: Exercise? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.note = note
        self.restSeconds = restSeconds
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
    var isPR: Bool
    var isCompleted: Bool
    /// 時間種目の継続秒数（time / cardio のみ。weight/bodyweight は nil）。
    var durationSeconds: Int? = nil
    /// 有酸素種目の距離km（cardio のみ。それ以外は nil）。
    var distanceKm: Double? = nil
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool

    var workoutExercise: WorkoutExercise?

    /// このセットのボリューム（重量 × レップ）。
    /// トレーニングボリューム。補助(アシスト)は自重を軽くする方向なので加重をボリュームに数えない。
    /// 荷重/通常ウェイトは weight×reps、自重のみは weight=0 で 0。
    var volume: Double {
        if workoutExercise?.exercise?.loadMode == .assisted { return 0 }
        return weight * Double(reps)
    }

    init(
        id: UUID = UUID(),
        setIndex: Int,
        weight: Double = 0,
        reps: Int = 0,
        isPR: Bool = false,
        isCompleted: Bool = false,
        durationSeconds: Int? = nil,
        distanceKm: Double? = nil,
        workoutExercise: WorkoutExercise? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.isPR = isPR
        self.isCompleted = isCompleted
        self.durationSeconds = durationSeconds
        self.distanceKm = distanceKm
        self.workoutExercise = workoutExercise
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
