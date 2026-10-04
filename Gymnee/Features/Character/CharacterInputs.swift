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
    /// 育成の現在値。**部屋とコーチで同じ式を使う**ための入口。
    /// 別々に組むと、コーチが部屋と違う数字を喋る。
    struct Growth: Equatable, Sendable {
        let totalExperience: Int
        let level: CharacterProgress.Level
        let stage: CharacterProgress.Stage
        let nextStage: CharacterProgress.NextStage?
        let energy: Int
        let streakWeeks: Int
    }

    static func growth(
        completedWorkouts: [Workout],
        pickups: [RoomPickupRecord],
        runs: [ExpeditionRun],
        weeklyGoal: Int
    ) -> Growth {
        let prs = prHistory(from: completedWorkouts)
        let sessions = sessions(from: completedWorkouts, prCountByWorkout: prs.byWorkout)
        let collectedIds = pickups.map(\.itemId)
        let totalExperience = CharacterProgress.totalExperience(
            sessions: sessions,
            pickupBonus: RoomPickup.totalExperience(collectedItemIds: collectedIds)
        )
        let level = CharacterProgress.level(totalExperience: totalExperience)
        let streak = StreakCalculator.currentWeeklyStreak(
            activeDays: completedWorkouts.map { $0.completedAt ?? $0.date }, weeklyGoal: weeklyGoal
        )
        return Growth(
            totalExperience: totalExperience,
            level: level,
            stage: CharacterProgress.stage(
                level: level.value, prCount: prs.total, weeklyStreakWeeks: streak.weeks
            ),
            nextStage: CharacterProgress.nextStage(
                level: level.value, prCount: prs.total, weeklyStreakWeeks: streak.weeks
            ),
            energy: Expedition.availableEnergy(
                sessions: sessions,
                spent: runs.reduce(0) { $0 + $1.energySpent },
                bonus: RoomPickup.totalEnergy(collectedItemIds: collectedIds)
            ),
            streakWeeks: streak.weeks
        )
    }

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

    /// 自己ベスト更新の履歴（セッション EXP のボーナスと進化条件の入力）。
    /// 保存済みの `PersonalRecord` は最新値の上書きで履歴を持たないため、記録から導き直す（`PRHistory`）。
    static func prHistory(from workouts: [Workout]) -> PRHistory.Result {
        PRHistory.replay(workouts.compactMap { workout in
            guard let done = workout.completedAt else { return nil }
            let sets = workout.exercises
                .sorted { $0.orderIndex < $1.orderIndex }
                .flatMap { we -> [PRHistory.SetInput] in
                    guard let exercise = we.exercise else { return [] }
                    return we.sets
                        .sorted { $0.setIndex < $1.setIndex }
                        .map {
                            PRHistory.SetInput(
                                exerciseId: exercise.id,
                                measurementType: exercise.measurementType,
                                loadMode: exercise.loadMode,
                                weight: $0.weight,
                                reps: $0.reps,
                                durationSeconds: $0.durationSeconds
                            )
                        }
                }
            return PRHistory.WorkoutInput(id: workout.id, completedAt: done, sets: sets)
        })
    }
}
