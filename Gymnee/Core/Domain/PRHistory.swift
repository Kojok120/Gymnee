import Foundation

/// 自己ベスト更新の履歴を、ワークアウトの記録から導き直す。
///
/// `PersonalRecord` は種目×指標ごとに「今の最高値」を1行で上書き保存しており、更新の履歴を持たない。
/// その行の件数や `workoutId` を育成の入力にしていたため、次の問題があった。
/// - 自己ベストを更新しても、ボーナスが前のワークアウトから移るだけで EXP が増えない
/// - 進化条件の「自己ベスト数」が更新回数ではなく、記録したことのある種目×指標の組み合わせ数になる
///   （同じメニューで重量を伸ばす人ほど進化が止まる）
///
/// 育成は「現実だけがエンジン」（`CharacterProgress`）なので、ここでも保存値ではなく
/// 記録を時系列に再生して、どの回で何件更新したかを数える。判定は記録時と同じ `PRDetector`。
enum PRHistory {
    struct SetInput: Equatable, Sendable {
        let exerciseId: UUID
        let measurementType: MeasurementType
        let loadMode: LoadMode
        let weight: Double
        let reps: Int
        let durationSeconds: Int?
    }

    struct WorkoutInput: Equatable, Sendable {
        let id: UUID
        let completedAt: Date
        /// 記録した順（種目の並び → セット番号）。
        let sets: [SetInput]
    }

    struct Result: Equatable, Sendable {
        /// ワークアウトごとの更新件数。同じ回の中で同じ種目×指標を何度伸ばしても 1 件と数える。
        let byWorkout: [UUID: Int]
        /// 更新件数の合計（進化条件の「自己ベスト」）。
        let total: Int
    }

    static func replay(_ workouts: [WorkoutInput]) -> Result {
        // 完了時刻順に再生する。同時刻は id で並べて、毎回同じ結果にする。
        let ordered = workouts.sorted {
            $0.completedAt == $1.completedAt ? $0.id.uuidString < $1.id.uuidString : $0.completedAt < $1.completedAt
        }
        var bests: [UUID: PRDetector.Bests] = [:]
        var byWorkout: [UUID: Int] = [:]
        var total = 0
        for workout in ordered {
            var improved = Set<String>()
            for set in workout.sets {
                let current = bests[set.exerciseId] ?? PRDetector.Bests()
                let detected = PRDetector.detect(
                    measurementType: set.measurementType,
                    weight: set.weight,
                    reps: set.reps,
                    durationSeconds: set.durationSeconds,
                    against: current,
                    loadMode: set.loadMode
                )
                guard !detected.isEmpty else { continue }
                bests[set.exerciseId] = current.applying(detected)
                for pr in detected {
                    improved.insert("\(set.exerciseId.uuidString)|\(pr.type.rawValue)")
                }
            }
            if !improved.isEmpty {
                byWorkout[workout.id] = improved.count
                total += improved.count
            }
        }
        return Result(byWorkout: byWorkout, total: total)
    }
}

extension PRDetector.Bests {
    /// 検出した自己ベストを反映した新しいベスト。補助は小さいほど良いので min を取る。
    func applying(_ detected: [PRDetector.DetectedPR]) -> PRDetector.Bests {
        var next = self
        for pr in detected {
            switch pr.type {
            case .maxWeight: next.maxWeight = max(next.maxWeight, pr.value)
            case .est1RM: next.est1RM = max(next.est1RM, pr.value)
            case .maxReps: next.maxReps = max(next.maxReps, pr.value)
            case .maxDuration: next.maxDuration = max(next.maxDuration, pr.value)
            case .minAssist: next.minAssist = min(next.minAssist, pr.value)
            }
        }
        return next
    }
}
