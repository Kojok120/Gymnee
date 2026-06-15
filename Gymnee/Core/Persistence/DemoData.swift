#if DEBUG
import Foundation
import SwiftData

/// DEBUG 専用のデモデータ投入＆検証ハーネス。製品ビルドには含まれない。
/// 起動引数 `-gymneeDemo` で来店/ワークアウトを投入し、`-gymneeScreen <name>` で特定画面を起動する。
enum DebugSupport {
    static var demoRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-gymneeDemo")
    }

    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-gymneeScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

enum DemoData {
    /// デモ来店・ワークアウトを冪等に投入する。
    @MainActor
    static func seedIfNeeded(_ context: ModelContext, userId: UUID) {
        let existing = (try? context.fetchCount(FetchDescriptor<Visit>(predicate: #Predicate { $0.userId == userId }))) ?? 0
        guard existing == 0 else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        // デモ用ジム（座標付き＝近隣補完が効く）。
        let gymA = Gym(name: "Gymnee 渋谷", chain: "Anytime Fitness", lat: 35.6595, lng: 139.7005, source: .user, createdBy: userId, isFavorite: true, isDirty: false)
        let gymB = Gym(name: "Gymnee 出張先・大阪", chain: "Gold's Gym", lat: 34.7025, lng: 135.4959, source: .user, createdBy: userId, isDirty: false)
        context.insert(gymA)
        context.insert(gymB)

        // 直近の来店パターン（連続記録が出るよう today/-1/-2 を含める）。
        let offsets = [0, 1, 2, 4, 6, 7, 9, 11, 14, 18, 21]
        for (idx, off) in offsets.enumerated() {
            guard let date = cal.date(byAdding: .day, value: -off, to: today) else { continue }
            let visit = Visit(
                userId: userId,
                visitedAt: cal.date(byAdding: .hour, value: 19, to: date) ?? date,
                gym: (off % 5 == 0) ? gymB : gymA,
                note: idx == 0 ? "胸の日。ベンチ更新！" : nil,
                isDirty: false
            )
            context.insert(visit)
        }

        // ワークアウト 1 件（種目・セット・PR 込み）。
        let bench = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "ベンチプレス" })))?.first
        let workout = Workout(userId: userId, date: today, name: "胸・三頭", completedAt: .now, isDirty: false)
        context.insert(workout)
        if let bench {
            let we = WorkoutExercise(orderIndex: 0, workout: workout, exercise: bench, isDirty: false)
            context.insert(we)
            let reps = [10, 8, 6]
            let weights = [60.0, 70.0, 80.0]
            for i in 0..<3 {
                let set = ExerciseSet(setIndex: i, weight: weights[i], reps: reps[i], type: .normal, isPR: i == 2, isCompleted: true, workoutExercise: we, isDirty: false)
                context.insert(set)
            }
        }

        try? context.save()
    }

    /// 検証用の進行中ワークアウト（種目・前回値オートフィル付き）を作って返す。
    @MainActor
    static func makeLoggerWorkout(_ context: ModelContext, userId: UUID) -> Workout {
        let workout = Workout(userId: userId, date: .now, name: "デモセッション", isDirty: false)
        context.insert(workout)
        let names = ["ベンチプレス", "スクワット"]
        for (i, name) in names.enumerated() {
            guard let ex = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })))?.first else { continue }
            let we = WorkoutExercise(orderIndex: i, workout: workout, exercise: ex, isDirty: false)
            context.insert(we)
            let prev = WorkoutMetrics.previousSets(for: ex, userId: userId, excludingWorkoutId: workout.id)
            if prev.isEmpty {
                context.insert(ExerciseSet(setIndex: 0, weight: 60, reps: 8, workoutExercise: we, isDirty: false))
                context.insert(ExerciseSet(setIndex: 1, weight: 60, reps: 8, workoutExercise: we, isDirty: false))
            } else {
                for (s, p) in prev.enumerated() {
                    context.insert(ExerciseSet(setIndex: s, weight: p.weight, reps: p.reps, type: p.type, workoutExercise: we, isDirty: false))
                }
            }
        }
        try? context.save()
        return workout
    }
}
#endif
