import Foundation
import SwiftData

/// 記録カードのルーラー（横スクロール等間隔）の「中心値」と刻みを算出する（記録リデザイン）。
/// 中心値は 履歴 → 既定 で決まる（ルーティンに候補値は保存しない）。ルーラーの値列は `rulerValues` で生成。
@MainActor
enum RecordSlots {
    /// カード初期化に使う中心値の束。
    struct Centers: Equatable {
        var weight: Double   // weight / bodyweight（加重）の中央
        var reps: Int        // reps の中央
        var duration: Int    // time の秒の中央
    }

    /// 種目・コンテキストから中心値を算出（履歴 → 既定）。
    static func centers(for exercise: Exercise, userId: UUID, excludingWorkoutId: UUID?) -> Centers {
        let type = exercise.measurementType
        let prev = WorkoutMetrics.previousSets(for: exercise, userId: userId, excludingWorkoutId: excludingWorkoutId)

        if type == .time {
            let dur = prev.compactMap { $0.durationSeconds }.first { $0 > 0 } ?? 30
            return Centers(weight: 0, reps: 0, duration: max(5, dur))
        }

        let weight: Double
        if type == .bodyweight {
            weight = prev.first.map { max(0, $0.weight) } ?? defaultWeight(exercise)   // 加重（0=自重のみ）
        } else {
            weight = prev.first(where: { $0.weight > 0 })?.weight ?? defaultWeight(exercise)
        }
        let reps = prev.first(where: { $0.reps > 0 })?.reps ?? 10
        return Centers(weight: weight, reps: reps, duration: 30)
    }

    /// 器具ごとの重量刻み。
    static func weightStep(_ exercise: Exercise) -> Double {
        switch exercise.equipment {
        case .machine, .cable: return 5
        case .kettlebell: return 4
        default: return 2.5
        }
    }

    /// 履歴が無いときの既定重量（ルーラーの初期中央）。
    static func defaultWeight(_ exercise: Exercise) -> Double {
        if exercise.measurementType == .bodyweight { return 0 }
        switch exercise.equipment {
        case .barbell: return 20
        case .dumbbell: return 5
        case .machine: return 10
        case .cable: return 10
        case .kettlebell: return 8
        case .bodyweight: return 0
        case .other: return 10
        }
    }

    /// ルーラーの値列（純関数）。center を必ず含む等差列、lowerBound 未満は除外。
    static func rulerValues(center: Double, step: Double, lowerBound: Double, count: Int = 30) -> [Double] {
        guard step > 0 else { return [center] }
        var result: [Double] = []
        for i in -count...count {
            let v = center + step * Double(i)
            if v >= lowerBound - 0.0001 { result.append((v * 100).rounded() / 100) }
        }
        return result.isEmpty ? [max(center, lowerBound)] : result
    }
}
