import Foundation

/// 完了ワークアウト → 育成ドメインの入力（`MuscleLoadInputs` と同じ役割）。
///
/// 集計そのものは `Core/Domain` の純粋関数だが、その手前の「SwiftData のワークアウトから
/// セット数・ボリュームを取り出す」部分は育成タブと DEBUG ハーネスの両方で要るのでここに置く。
enum CharacterInputs {

    /// 完了済みワークアウトからセッション入力を作る。
    /// 日付は `completedAt` に一本化する（`date` は後追い記録でズレることがある）。
    /// ボリュームは既存の総挙上量（プロフィールの実績）と同じ数え方に合わせ、
    /// 完了ワークアウトに属するセットをすべて数える。
    static func sessions(
        from workouts: [Workout],
        prCountByWorkout: [UUID: Int] = [:]
    ) -> [CharacterProgress.SessionInput] {
        var result: [CharacterProgress.SessionInput] = []
        for workout in workouts {
            guard let done = workout.completedAt else { continue }
            var setCount = 0
            var volume: Double = 0
            for we in workout.exercises {
                for set in we.sets {
                    setCount += 1
                    let value = set.volume
                    if value.isFinite, value > 0 { volume += value }
                }
            }
            guard setCount > 0 else { continue }
            result.append(
                CharacterProgress.SessionInput(
                    completedAt: done,
                    completedSets: setCount,
                    volumeKg: volume,
                    prCount: prCountByWorkout[workout.id] ?? 0
                )
            )
        }
        return result
    }

    /// 完了済みワークアウトの部位別累積ボリューム（ステータス算出の入力）。
    static func volumeByMuscle(from workouts: [Workout]) -> [MuscleGroup: Double] {
        var result: [MuscleGroup: Double] = [:]
        for workout in workouts where workout.completedAt != nil {
            for we in workout.exercises {
                guard let group = we.exercise?.muscleGroup else { continue }
                for set in we.sets {
                    let value = set.volume
                    guard value.isFinite, value > 0 else { continue }
                    result[group, default: 0] += value
                }
            }
        }
        return result
    }

    /// PR をワークアウト単位の件数に畳む（セッション EXP のボーナス入力）。
    static func prCountByWorkout(_ records: [PersonalRecord]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for record in records {
            guard let id = record.workoutId else { continue }
            result[id, default: 0] += 1
        }
        return result
    }
}
