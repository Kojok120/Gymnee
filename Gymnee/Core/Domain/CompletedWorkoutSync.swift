import Foundation

/// 記録画面での変更を、いつサーバーへ送るかを決める純粋ロジック（#170）。
///
/// - 下書き（`completedAt == nil`）: まだサーバーに無いので、ここでは何も送らない。
///   完了ボタンでまとめて送る（中断した記録をサーバーに残さないため）。
/// - 完了済みの記録を開き直して直したとき: 変更をその場で送る。
///   以前は完了ボタンを押したときに「残っている行の upsert」だけを送っていたため、
///   消したセットの削除がサーバーに届かず、完了を押さずに戻ると変更自体も届かなかった。
///   差分 pull は削除を伝えないので（AGENTS.md「差分同期の不変条件」）、削除は必ずここで積む。
enum CompletedWorkoutSync {

    /// 記録画面で起きた変更。SwiftData の行を消したあとは中身を読めないので、id は消す前に控えて渡す。
    enum Edit: Equatable, Sendable {
        /// セットを足した。種目の行（WorkoutExercise）が新しくできた場合も、既存の場合も同じ。
        case added(set: Row, workoutExercise: Row, exercise: Row?)
        /// セットの値を直した。
        case edited(set: Row)
        /// セットを消した。最後の 1 セットだったときは種目の行も消える（`removedWorkoutExercise`）。
        case deleted(setId: UUID, removedWorkoutExercise: UUID?)
        /// 完了時に、セットが 0 件になった種目の行を掃除した。
        case removedEmptyWorkoutExercise(id: UUID)
    }

    /// 送る行の id と更新時刻。
    struct Row: Equatable, Sendable {
        var id: UUID
        var updatedAt: Date
    }

    /// 変更をサーバーへ送る送信待ちに変える。下書きなら空を返す。
    ///
    /// - Parameters:
    ///   - isCompleted: 変更した時点で、その記録が完了済みか（`Workout.completedAt != nil`）。
    ///   - includesExercise: 種目（`exercises`）も送るか。プリセット種目は送らない（サーバーに既にある）。
    static func changes(for edit: Edit, isCompleted: Bool, now: Date = .now) -> [PendingChange] {
        guard isCompleted else { return [] }
        switch edit {
        case let .added(set, workoutExercise, exercise):
            // 親 → 子の順に積む（push 側も依存順で送るが、積む順でも崩さない）。
            var result: [PendingChange] = []
            if let exercise {
                result.append(PendingChange(entity: "exercises", recordId: exercise.id, operation: .upsert, updatedAt: exercise.updatedAt))
            }
            result.append(PendingChange(entity: "workout_exercises", recordId: workoutExercise.id, operation: .upsert, updatedAt: workoutExercise.updatedAt))
            result.append(PendingChange(entity: "exercise_sets", recordId: set.id, operation: .upsert, updatedAt: set.updatedAt))
            return result
        case let .edited(set):
            return [PendingChange(entity: "exercise_sets", recordId: set.id, operation: .upsert, updatedAt: set.updatedAt)]
        case let .deleted(setId, removedWorkoutExercise):
            // 種目の行を消せばサーバー側で連鎖削除されるが、セットの削除も積む。
            // 種目の行の削除が先に失敗しても、セットだけは確実に消えるようにするため。
            var result = [PendingChange(entity: "exercise_sets", recordId: setId, operation: .delete, updatedAt: now)]
            if let removedWorkoutExercise {
                result.append(PendingChange(entity: "workout_exercises", recordId: removedWorkoutExercise, operation: .delete, updatedAt: now))
            }
            return result
        case let .removedEmptyWorkoutExercise(id):
            return [PendingChange(entity: "workout_exercises", recordId: id, operation: .delete, updatedAt: now)]
        }
    }
}
