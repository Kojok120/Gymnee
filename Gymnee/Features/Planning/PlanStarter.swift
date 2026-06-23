import Foundation
import SwiftData

/// 計画(PlannedWorkout)を実記録(Workout)に変換する共通ロジック（§6.5）。
/// WeekPlanner と 記録ホームの「今日の計画」の双方から使う。
enum PlanStarter {
    /// 計画から実記録を作成し、AI詳細→ルーティン→空 の優先で種目をプリフィル。計画は完了扱いにする。
    @MainActor
    static func start(_ plan: PlannedWorkout, userId: UUID, routines: [Routine], context: ModelContext) -> Workout {
        let workout = Workout(userId: userId, date: .now, name: plan.title, routineId: plan.routineId)
        context.insert(workout)

        if let json = plan.detailJSON, let data = json.data(using: .utf8),
           let exs = try? JSONDecoder().decode([SupabaseClient.PlanExercise].self, from: data), !exs.isEmpty {
            // AI が組んだ種目＋セット＋重量/レップ。
            for (i, pe) in exs.enumerated() {
                let exercise = findOrCreateExercise(name: pe.name, muscleGroup: pe.muscleGroup, userId: userId, context: context)
                let we = WorkoutExercise(orderIndex: i, workout: workout, exercise: exercise)
                context.insert(we)
                for s in 0..<max(pe.sets, 1) {
                    context.insert(ExerciseSet(setIndex: s, weight: pe.weight, reps: pe.reps, workoutExercise: we))
                }
            }
        } else if let rid = plan.routineId, let routine = routines.first(where: { $0.id == rid }) {
            // ルーティンから（種目＋前回値）。
            let ordered = routine.routineExercises.sorted { $0.orderIndex < $1.orderIndex }
            for (i, re) in ordered.enumerated() {
                guard let exercise = re.exercise else { continue }
                let we = WorkoutExercise(orderIndex: i, restSeconds: re.restSeconds, workout: workout, exercise: exercise)
                context.insert(we)
                let prev = WorkoutMetrics.previousSets(for: exercise, userId: userId, excludingWorkoutId: workout.id)
                let setCount = max(re.targetSets, prev.count)
                for s in 0..<setCount {
                    let p = s < prev.count ? prev[s] : nil
                    context.insert(ExerciseSet(setIndex: s, weight: p?.weight ?? 0, reps: p?.reps ?? 0, type: p?.type ?? .normal, workoutExercise: we))
                }
            }
        }

        plan.isDone = true
        plan.completedWorkoutId = workout.id // 計画↔実績をリンク
        plan.updatedAt = .now
        try? context.save()
        return workout
    }

    /// 種目名から既存を引く。無ければ本人カスタム種目を作成。
    @MainActor
    static func findOrCreateExercise(name: String, muscleGroup: String?, userId: UUID, context: ModelContext) -> Exercise {
        if let existing = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })))?.first {
            return existing
        }
        let mg = muscleGroup.flatMap { MuscleGroup(rawValue: $0) } ?? .fullBody
        let exercise = Exercise(name: name, muscleGroup: mg, equipment: .other, isCustom: true, createdBy: userId)
        context.insert(exercise)
        return exercise
    }
}
