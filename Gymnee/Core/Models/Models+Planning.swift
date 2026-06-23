import Foundation
import SwiftData

/// 計画されたワークアウト（§6.5 計画）。カレンダー連携で予定に合わせて配置・再配置する。
/// 現状は端末ローカル（同期対象外）。マルチデバイス同期は将来対応。
@Model
final class PlannedWorkout {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    /// 計画日（その日の予定）。
    var date: Date
    var title: String
    /// 紐づくルーティン（任意）。
    var routineId: UUID?
    var note: String?
    /// AI が組んだ種目内容（[PlanExercise] の JSON）。開始時にこの内容で実記録をプリフィルする。
    var detailJSON: String?
    var isDone: Bool
    /// 開始して実記録に変わったワークアウトの id（計画↔実績のリンク／達成率算出の根拠）。
    var completedWorkoutId: UUID?
    var updatedAt: Date
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        userId: UUID,
        date: Date,
        title: String,
        routineId: UUID? = nil,
        note: String? = nil,
        isDone: Bool = false,
        completedWorkoutId: UUID? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.date = date
        self.title = title
        self.routineId = routineId
        self.note = note
        self.isDone = isDone
        self.completedWorkoutId = completedWorkoutId
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
