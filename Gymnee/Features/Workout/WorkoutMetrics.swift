import Foundation
import SwiftData

/// ワークアウトの SwiftData 連携ヘルパ（前回値オートフィル・PR 検出・PR 永続化）。
/// 純粋判定は Domain（PRDetector / OneRepMax）に委譲し、ここはモデル走査と永続化のみ担う。
@MainActor
enum WorkoutMetrics {
    /// 指定種目・ユーザーの全セット（メモリ走査）。
    static func allSets(for exercise: Exercise, userId: UUID) -> [ExerciseSet] {
        exercise.workoutExercises
            .filter { $0.workout?.userId == userId }
            .flatMap { $0.sets }
    }

    /// 前回値オートフィル（§6.5 の生命線）。直近（当該ワークアウト除く）のセットを返す。
    static func previousSets(for exercise: Exercise, userId: UUID, excludingWorkoutId: UUID?) -> [ExerciseSet] {
        let candidates = exercise.workoutExercises.filter {
            $0.workout?.userId == userId && $0.workout?.id != excludingWorkoutId
        }
        let mostRecent = candidates.max {
            ($0.workout?.date ?? .distantPast) < ($1.workout?.date ?? .distantPast)
        }
        return (mostRecent?.sets ?? []).sorted { $0.setIndex < $1.setIndex }
    }

    /// 直近 N セッションの代表セット（最重量の作業セット）。インライン履歴表示用。
    static func recentTopSets(for exercise: Exercise, userId: UUID, excludingWorkoutId: UUID?, limit: Int = 3) -> [(date: Date, weight: Double, reps: Int)] {
        let sessions = exercise.workoutExercises
            .filter { $0.workout?.userId == userId && $0.workout?.id != excludingWorkoutId }
            .compactMap { we -> (date: Date, weight: Double, reps: Int)? in
                guard let date = we.workout?.date else { return nil }
                let working = we.sets.filter { $0.weight > 0 }
                guard let top = working.max(by: { $0.weight < $1.weight }) else { return nil }
                return (date, top.weight, top.reps)
            }
            .sorted { $0.date > $1.date }
        return Array(sessions.prefix(limit))
    }

    /// 種目の履歴ベスト推定1RM（%1RM 提案の基準）。
    static func bestE1RM(for exercise: Exercise, userId: UUID, excludingWorkoutId: UUID?) -> Double {
        var best = 0.0
        for we in exercise.workoutExercises where we.workout?.userId == userId && we.workout?.id != excludingWorkoutId {
            for s in we.sets where s.weight > 0 && s.reps > 0 {
                best = max(best, OneRepMax.estimate(weight: s.weight, reps: s.reps))
            }
        }
        return best
    }

    /// 現在ベスト（PR 検出の基準）。候補セットを除外して履歴から算出。
    /// 計測タイプによって使う軸が違うため、利用可能な軸はすべて集計し detect 側で取捨する。
    static func bests(for exercise: Exercise, userId: UUID, excludingSetId: UUID?) -> PRDetector.Bests {
        var b = PRDetector.Bests()
        for s in allSets(for: exercise, userId: userId) where s.id != excludingSetId {
            if s.weight > 0 && s.reps > 0 {
                b.maxWeight = max(b.maxWeight, s.weight)
                b.est1RM = max(b.est1RM, OneRepMax.estimate(weight: s.weight, reps: s.reps))
            }
            if s.reps > 0 {
                b.maxReps = max(b.maxReps, Double(s.reps))
            }
            if let d = s.durationSeconds, d > 0 {
                b.maxDuration = max(b.maxDuration, Double(d))
            }
        }
        return b
    }

    /// セット完了時の PR 検出＋永続化。検出した PR 種別を返す（通知/トースト用）。
    @discardableResult
    static func evaluatePR(
        set: ExerciseSet,
        exercise: Exercise,
        workout: Workout,
        userId: UUID,
        context: ModelContext,
        sync: LocalSyncEngine
    ) -> [PRDetector.DetectedPR] {
        let bests = bests(for: exercise, userId: userId, excludingSetId: set.id)
        let detected = PRDetector.detect(
            measurementType: exercise.measurementType,
            weight: set.weight,
            reps: set.reps,
            durationSeconds: set.durationSeconds,
            against: bests
        )
        set.isPR = !detected.isEmpty
        for pr in detected {
            upsertPR(type: pr.type, value: pr.value, exercise: exercise, workout: workout, userId: userId, context: context, sync: sync)
        }
        return detected
    }

    /// PersonalRecord を upsert（同種別は最大値を保持）。
    private static func upsertPR(
        type: PRType,
        value: Double,
        exercise: Exercise,
        workout: Workout,
        userId: UUID,
        context: ModelContext,
        sync: LocalSyncEngine
    ) {
        let existing = exercise.personalRecords.first { $0.typeRaw == type.rawValue && $0.userId == userId }
        if let existing {
            guard value > existing.value else { return }
            existing.value = value
            existing.achievedAt = .now
            existing.workoutId = workout.id
            existing.updatedAt = .now
            existing.isDirty = true
            sync.enqueue(PendingChange(entity: "personal_records", recordId: existing.id, operation: .upsert, updatedAt: existing.updatedAt))
        } else {
            let pr = PersonalRecord(userId: userId, type: type, value: value, workoutId: workout.id, exercise: exercise)
            context.insert(pr)
            sync.enqueue(PendingChange(entity: "personal_records", recordId: pr.id, operation: .upsert, updatedAt: pr.updatedAt))
        }
    }
}
