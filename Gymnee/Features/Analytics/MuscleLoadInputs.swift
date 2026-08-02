import Foundation

/// 完了ワークアウト → 部位別の集計入力（`MuscleFatigue` / `WeeklyMuscleLoad` 共通）。
///
/// 集計そのものは `Core/Domain` の純粋関数だが、その手前の「SwiftData のワークアウトから
/// 部位×セット数を取り出す」部分は分析画面と DEBUG ハーネスの両方で要るのでここに置く。
enum MuscleLoadInputs {

    /// 完了済みワークアウトから部位ごとのセッションを組み立てる。
    /// 日付は `completedAt` に一本化する（`date` は後追い記録でズレることがある）。
    /// 同一ワークアウト内の同じ部位はセット数を合算する。
    static func sessionEntries(from workouts: [Workout]) -> [MuscleFatigue.SessionEntry] {
        var result: [MuscleFatigue.SessionEntry] = []
        for w in workouts {
            guard let done = w.completedAt else { continue }
            var setsByMuscle: [MuscleGroup: Int] = [:]
            for we in w.exercises {
                guard let muscle = we.exercise?.muscleGroup, !we.sets.isEmpty else { continue }
                setsByMuscle[muscle, default: 0] += we.sets.count
            }
            for (muscle, count) in setsByMuscle {
                result.append(MuscleFatigue.SessionEntry(muscle: muscle, completedAt: done, setCount: count))
            }
        }
        return result
    }
}
