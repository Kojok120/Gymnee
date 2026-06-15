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

    /// 現在ベスト（PR 検出の基準）。候補セットを除外して履歴から算出。
    static func bests(for exercise: Exercise, userId: UUID, excludingSetId: UUID?) -> PRDetector.Bests {
        var b = PRDetector.Bests()
        for s in allSets(for: exercise, userId: userId)
        where s.id != excludingSetId && s.type != .warmup && s.weight > 0 && s.reps > 0 {
            b.maxWeight = max(b.maxWeight, s.weight)
            b.maxReps = max(b.maxReps, Double(s.reps))
            b.est1RM = max(b.est1RM, OneRepMax.estimate(weight: s.weight, reps: s.reps))
            b.maxVolume = max(b.maxVolume, s.volume)
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
        let detected = PRDetector.detect(weight: set.weight, reps: set.reps, type: set.type, against: bests)
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
