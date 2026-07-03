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
        var duration: Int    // time は秒、cardio は分の中央
        var distanceKm: Double = 0  // cardio の距離km の中央
    }

    /// 種目・コンテキストから中心値を算出（履歴 → 既定）。
    static func centers(for exercise: Exercise, userId: UUID, excludingWorkoutId: UUID?) -> Centers {
        let type = exercise.measurementType
        let prev = WorkoutMetrics.previousSets(for: exercise, userId: userId, excludingWorkoutId: excludingWorkoutId)

        if type == .time {
            let dur = prev.compactMap { $0.durationSeconds }.first { $0 > 0 } ?? 30
            return Centers(weight: 0, reps: 0, duration: max(5, dur))
        }

        if type == .cardio {
            let dist = prev.compactMap { $0.distanceKm }.first { $0 > 0 } ?? 3
            let mins = prev.compactMap { $0.durationSeconds }.first { $0 > 0 }.map { $0 / 60 } ?? 30
            return Centers(weight: 0, reps: 0, duration: max(1, mins), distanceKm: max(0.5, dist))
        }

        let weight: Double
        if type == .bodyweight {
            // 符号付き（−=補助 / 0=自重 / ＋=加重）。前回値をそのまま初期中央に。
            weight = prev.first?.weight ?? defaultWeight(exercise)
        } else {
            weight = prev.first(where: { $0.weight > 0 })?.weight ?? defaultWeight(exercise)
        }
        let reps = prev.first(where: { $0.reps > 0 })?.reps ?? 10
        return Centers(weight: weight, reps: reps, duration: 30)
    }

    /// 重量刻み。プリセットは種目別レビュー値（ExerciseDefaults）、無ければ器具既定。
    /// ダンベルはレイズ/カール系の推奨値が2〜5kg域のため1kg刻み（1kg刻みラックの実態にも一致）。
    static func weightStep(_ exercise: Exercise) -> Double {
        if let entry = ExerciseDefaults.entry(for: exercise.name) { return entry.weightStep }
        switch exercise.equipment {
        case .machine, .cable: return 5
        case .kettlebell: return 4
        case .dumbbell: return 1
        default: return 2.5
        }
    }

    /// 履歴が無いときの既定重量（ルーラーの初期中央）。
    /// プリセットは種目別レビュー値（ExerciseDefaults）、無ければ器具既定。
    /// 自重系は符号付き（補助スタイルの種目は補助側 −10 から始める）。
    static func defaultWeight(_ exercise: Exercise) -> Double {
        if let entry = ExerciseDefaults.entry(for: exercise.name) { return entry.startWeight }
        if exercise.measurementType == .bodyweight {
            return exercise.loadMode == .assisted ? -10 : 0
        }
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

    /// 重量ルーラーの値列。器具・種目特性で刻みが一様でないケースを吸収する。
    /// - 自重（加重/補助）: −補助（マシンスタック5kg刻み）〜 0=自重 〜 ＋加重（プレート2.5kg刻み）の一本軸
    /// - ダンベル: 10kg までは 1kg 刻み（固定式ラックの実態）、10kg 超は偶数の 2kg 刻み
    /// - その他: 器具/種目別の等差列（weightStep）
    static func weightRulerValues(for exercise: Exercise, center: Double) -> [Double] {
        if exercise.measurementType == .bodyweight, exercise.loadMode != .none {
            return piecewiseValues(segments: [(-60, 0, 5), (0, 60, 2.5)], center: center)
        }
        if exercise.equipment == .dumbbell {
            return piecewiseValues(segments: [(0, 10, 1), (10, 60, 2)], center: center)
        }
        return rulerValues(center: center, step: weightStep(exercise), lowerBound: 0)
    }

    /// 区分ごとに刻みが違う値列（純関数）。区間は (from, to, step) の昇順・境界は重複排除。
    /// center が区間外/グリッド外（キーパッド学習値）でも必ず含め、端の区間の刻みで範囲を延長する。
    static func piecewiseValues(segments: [(from: Double, to: Double, step: Double)], center: Double) -> [Double] {
        var set = Set<Double>()
        func norm(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        for seg in segments where seg.step > 0 && seg.to > seg.from {
            var v = seg.from
            while v <= seg.to + 0.0001 {
                set.insert(norm(v))
                v += seg.step
            }
        }
        // center が範囲外なら端の刻みで延長（キーパッドで大きな値を学習したケース）。
        if let first = segments.first, let last = segments.last {
            var v = last.to
            while v < center - 0.0001 {
                v += last.step
                set.insert(norm(v))
            }
            v = first.from
            while v > center + 0.0001 {
                v -= first.step
                set.insert(norm(v))
            }
        }
        if center.isFinite { set.insert(norm(center)) }
        return set.sorted()
    }
}
