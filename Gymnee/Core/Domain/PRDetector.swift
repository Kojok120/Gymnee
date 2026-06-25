import Foundation

/// PR 自動検出（§6.5）。あるセットが既存ベストを更新したかを判定する。純粋ロジックでテスト対象。
enum PRDetector {
    /// 種目ごとの現在ベスト（4 種別）。未記録は 0。
    struct Bests: Equatable, Sendable {
        var maxWeight: Double = 0
        var maxReps: Double = 0
        var est1RM: Double = 0
        var maxVolume: Double = 0
    }

    /// 検出された 1 件の PR。
    struct DetectedPR: Equatable, Sendable {
        let type: PRType
        let value: Double
    }

    /// 候補セットが更新した PR を返す（ウォームアップは対象外）。
    /// - Parameters:
    ///   - weight: セット重量。
    ///   - reps: セットレップ。
    ///   - bests: 現在のベスト。
    ///   - formula: 1RM 推定式。
    static func detect(
        weight: Double,
        reps: Int,
        against bests: Bests,
        formula: OneRepMax.Formula = .epley
    ) -> [DetectedPR] {
        guard weight > 0, reps >= 1 else { return [] }

        var results: [DetectedPR] = []

        if weight > bests.maxWeight {
            results.append(DetectedPR(type: .maxWeight, value: weight))
        }
        if Double(reps) > bests.maxReps {
            results.append(DetectedPR(type: .maxReps, value: Double(reps)))
        }
        let est = OneRepMax.estimate(weight: weight, reps: reps, formula: formula)
        if est > bests.est1RM {
            results.append(DetectedPR(type: .est1RM, value: est))
        }
        let volume = weight * Double(reps)
        if volume > bests.maxVolume {
            results.append(DetectedPR(type: .maxVolume, value: volume))
        }
        return results
    }
}
