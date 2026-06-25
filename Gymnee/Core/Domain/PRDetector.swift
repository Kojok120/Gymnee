import Foundation

/// PR 自動検出（§6.5）。あるセットが既存ベストを更新したかを判定する。純粋ロジックでテスト対象。
enum PRDetector {
    /// 種目ごとの現在ベスト。計測タイプごとに使う軸が違う。未記録は 0。
    struct Bests: Equatable, Sendable {
        var maxWeight: Double = 0      // ウェイト種目
        var est1RM: Double = 0         // ウェイト種目
        var maxReps: Double = 0        // 自重種目
        var maxDuration: Double = 0    // 時間種目（秒）
    }

    /// 検出された 1 件の PR。
    struct DetectedPR: Equatable, Sendable {
        let type: PRType
        let value: Double
    }

    /// 候補セットが更新した PR を返す。計測タイプに応じて意味のある指標のみ判定する。
    /// - ウェイト: 最大重量 ＋ 推定1RM（重量↑もレップ↑も拾う）。
    /// - 自重: 最大レップ。
    /// - 時間: 最長時間（秒）。
    static func detect(
        measurementType: MeasurementType,
        weight: Double,
        reps: Int,
        durationSeconds: Int?,
        against bests: Bests,
        formula: OneRepMax.Formula = .epley
    ) -> [DetectedPR] {
        var results: [DetectedPR] = []

        switch measurementType {
        case .weight:
            guard weight > 0, reps >= 1 else { return [] }
            if weight > bests.maxWeight {
                results.append(DetectedPR(type: .maxWeight, value: weight))
            }
            let est = OneRepMax.estimate(weight: weight, reps: reps, formula: formula)
            if est > bests.est1RM {
                results.append(DetectedPR(type: .est1RM, value: est))
            }
        case .bodyweight:
            guard reps >= 1 else { return [] }
            if Double(reps) > bests.maxReps {
                results.append(DetectedPR(type: .maxReps, value: Double(reps)))
            }
        case .time:
            let secs = Double(durationSeconds ?? 0)
            guard secs > 0 else { return [] }
            if secs > bests.maxDuration {
                results.append(DetectedPR(type: .maxDuration, value: secs))
            }
        }
        return results
    }
}
