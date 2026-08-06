#if DEBUG
import Foundation
import SwiftData

/// DEBUG 専用のデモデータ投入＆検証ハーネス。製品ビルドには含まれない。
/// 起動引数 `-gymneeDemo` でワークアウトを投入し、`-gymneeScreen <name>` で特定画面を起動する。
enum DebugSupport {
    static var demoRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-gymneeDemo")
    }

    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-gymneeScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// 招待リンクの受信をシミュレータで再現する（AASA 未配備でも遷移を検証できる）。
    /// 例: `-gymneeInvite <uuid>` → 保留招待として保存され、ソーシャル画面が消費する。
    static var inviteUserId: UUID? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-gymneeInvite"), i + 1 < args.count else { return nil }
        return UUID(uuidString: args[i + 1])
    }
}

enum DemoData {
    /// デモワークアウトを冪等に投入する。
    @MainActor
    static func seedIfNeeded(_ context: ModelContext, userId: UUID) {
        let existing = (try? context.fetchCount(FetchDescriptor<Workout>(predicate: #Predicate { $0.userId == userId }))) ?? 0
        guard existing == 0 else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        // フォローのデモ。
        context.insert(Follow(followerId: userId, followeeId: UUID(), followeeDisplayName: "ゆうき", isDirty: false))

        // ベンチプレスの履歴（強度進捗・PRタイムライン用に複数セッション）。
        // ラットプルダウンも混ぜて完了種目を3種以上にする（「よくやる種目」セクションの表示検証用）。
        let bench = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "ベンチプレス" })))?.first
        let squat = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "スクワット" })))?.first
        let lat = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "ラットプルダウン" })))?.first
        // (日数前, トップ重量) を過去→現在で漸増。
        // 直近は「今日」にする（人体図の疲労度・連続記録など“直後の状態”を検証できるように）。
        let benchHistory: [(Int, Double)] = [(23, 70), (16, 72.5), (9, 77.5), (0, 80)]
        for (off, topWeight) in benchHistory {
            guard let date = cal.date(byAdding: .day, value: -off, to: today) else { continue }
            let workout = Workout(userId: userId, date: date, name: "胸・三頭", completedAt: date, isDirty: false)
            context.insert(workout)
            if let bench {
                let we = WorkoutExercise(orderIndex: 0, workout: workout, exercise: bench, isDirty: false)
                context.insert(we)
                let weights = [topWeight - 20, topWeight - 10, topWeight]
                let reps = [10, 8, 6]
                for i in 0..<3 {
                    context.insert(ExerciseSet(setIndex: i, weight: weights[i], reps: reps[i], isPR: i == 2 && off == 0, isCompleted: true, workoutExercise: we, isDirty: false))
                }
            }
            if let squat, off == 0 {
                let we = WorkoutExercise(orderIndex: 1, workout: workout, exercise: squat, isDirty: false)
                context.insert(we)
                for i in 0..<3 {
                    context.insert(ExerciseSet(setIndex: i, weight: 100, reps: 5, isCompleted: true, workoutExercise: we, isDirty: false))
                }
            }
            if let lat, off <= 16 {
                let we = WorkoutExercise(orderIndex: 2, workout: workout, exercise: lat, isDirty: false)
                context.insert(we)
                for i in 0..<3 {
                    context.insert(ExerciseSet(setIndex: i, weight: 55, reps: 10, isCompleted: true, workoutExercise: we, isDirty: false))
                }
            }
        }

        // 直近の連続記録（連続日数リング・カレンダーの埋まり・今週の積み上げを実データで検証するため、
        // 今日から遡って途切れない日を作る）。ベンチ履歴が飛び飛びなだけでは連続 1 日にしかならない。
        let recentStreak: [(Int, String, String, Double, Int)] = [
            (1, "脚", "スクワット", 100, 8),
            (2, "背中", "ラットプルダウン", 55, 12),
        ]
        for (off, name, exerciseName, weight, reps) in recentStreak {
            guard let date = cal.date(byAdding: .day, value: -off, to: today),
                  let ex = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == exerciseName })))?.first
            else { continue }
            let workout = Workout(userId: userId, date: date, name: name, completedAt: date, isDirty: false)
            context.insert(workout)
            let we = WorkoutExercise(orderIndex: 0, workout: workout, exercise: ex, isDirty: false)
            context.insert(we)
            for i in 0..<3 {
                context.insert(ExerciseSet(setIndex: i, weight: weight, reps: reps, isCompleted: true, workoutExercise: we, isDirty: false))
            }
        }

        // 今日の計画（記録画面の「今日の計画」タブ・週プランナーの検証用）。
        // AI 計画と同じく detailJSON に種目を持たせる（計画タブはこの JSON からカードを作る）。
        let planExercises = """
        [{"name":"ベンチプレス","muscleGroup":"chest","sets":3,"reps":8,"weight":75},\
        {"name":"ラットプルダウン","muscleGroup":"back","sets":3,"reps":10,"weight":55},\
        {"name":"スクワット","muscleGroup":"legs","sets":3,"reps":5,"weight":100}]
        """
        let plan = PlannedWorkout(userId: userId, date: today, title: "胸の日", isDirty: false)
        plan.detailJSON = planExercises
        context.insert(plan)

        // 身体メトリクス（体重推移チャート＋サイズ）のデモ。
        let bodyHistory: [(Int, Double, Double)] = [(120, 75.0, 18.0), (90, 74.2, 17.2), (60, 73.5, 16.5), (30, 73.0, 16.0), (1, 72.5, 15.0)]
        for (off, w, bf) in bodyHistory {
            guard let date = cal.date(byAdding: .day, value: -off, to: today) else { continue }
            context.insert(BodyMetric(userId: userId, date: date, weight: w, bodyFat: bf, measurements: ["腕": 38, "胸": 102, "ウエスト": 78], isDirty: false))
        }

        // 進捗写真（グリッド・月次グルーピング・比較）のデモ。実画像は無いためプレースホルダ表示になる。
        let photoOffsets = [115, 85, 55, 25, 2]
        for (i, off) in photoOffsets.enumerated() {
            guard let date = cal.date(byAdding: .day, value: -off, to: today) else { continue }
            context.insert(ProgressPhoto(userId: userId, date: date, localPhotoFilename: "demo_\(i).jpg", visibility: i % 2 == 0 ? .private : .friends, isDirty: false))
        }

        // PersonalRecord（PRタイムライン用）。
        if let bench {
            context.insert(PersonalRecord(userId: userId, type: .maxWeight, value: 80, achievedAt: cal.date(byAdding: .day, value: -2, to: today) ?? today, exercise: bench, isDirty: false))
            context.insert(PersonalRecord(userId: userId, type: .est1RM, value: OneRepMax.estimate(weight: 80, reps: 6), achievedAt: cal.date(byAdding: .day, value: -2, to: today) ?? today, exercise: bench, isDirty: false))
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
                    context.insert(ExerciseSet(setIndex: s, weight: p.weight, reps: p.reps, workoutExercise: we, isDirty: false))
                }
            }
        }
        try? context.save()
        return workout
    }
}
#endif
