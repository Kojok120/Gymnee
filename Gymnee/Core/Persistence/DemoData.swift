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

    /// 招待リンクの受信をシミュレータで再現する（AASA 未配備でも遷移を検証できる）。
    /// 例: `-gymneeInvite <uuid>` → 保留招待として保存され、ソーシャル画面が消費する。
    static var inviteUserId: UUID? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-gymneeInvite"), i + 1 < args.count else { return nil }
        return UUID(uuidString: args[i + 1])
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
            // 合トレのデモ（直近の来店に相手をタグ付け）。
            if idx == 1 {
                context.insert(VisitPartner(partnerUserId: UUID(), partnerDisplayName: "ゆうき", visit: visit))
            }
        }

        // フォローのデモ。
        context.insert(Follow(followerId: userId, followeeId: UUID(), followeeDisplayName: "ゆうき", isDirty: false))

        // ベンチプレスの履歴（強度進捗・PRタイムライン用に複数セッション）。
        // ラットプルダウンも混ぜて完了種目を3種以上にする（「よくやる種目」セクションの表示検証用）。
        let bench = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "ベンチプレス" })))?.first
        let squat = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "スクワット" })))?.first
        let lat = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "ラットプルダウン" })))?.first
        // (日数前, トップ重量) を過去→現在で漸増。
        let benchHistory: [(Int, Double)] = [(23, 70), (16, 72.5), (9, 77.5), (2, 80)]
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
                    context.insert(ExerciseSet(setIndex: i, weight: weights[i], reps: reps[i], isPR: i == 2 && off == 2, isCompleted: true, workoutExercise: we, isDirty: false))
                }
            }
            if let squat, off == 2 {
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
