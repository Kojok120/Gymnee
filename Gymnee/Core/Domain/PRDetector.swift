import Foundation

/// PR 自動検出（§6.5）。あるセットが既存ベストを更新したかを判定する。純粋ロジックでテスト対象。
enum PRDetector {
    /// 種目ごとの現在ベスト。計測タイプごとに使う軸が違う。未記録は 0（minAssist のみ ∞）。
    struct Bests: Equatable, Sendable {
        var maxWeight: Double = 0      // ウェイト種目／自重(荷重)
        var est1RM: Double = 0         // ウェイト種目
        var maxReps: Double = 0        // 自重種目
        var maxDuration: Double = 0    // 時間種目（秒）
        var minAssist: Double = .greatestFiniteMagnitude  // 自重(補助): 補助の最小（軽いほど良い）。未記録は ∞
    }

    /// 検出された 1 件の PR。
    struct DetectedPR: Equatable, Sendable {
        let type: PRType
        let value: Double
    }

    /// 候補セットが更新した PR を返す。計測タイプ（＋自重の荷重モード）に応じて意味のある指標のみ判定する。
    /// - ウェイト: 最大重量 ＋ 推定1RM（重量↑もレップ↑も拾う）。
    /// - 自重・自重のみ: 最大レップ。
    /// - 自重・荷重: 最大荷重(kg)。
    /// - 自重・補助: 最小補助(kg)（軽いほど強い＝より小さい値で更新）。
    /// - 時間: 最長時間（秒）。
    static func detect(
        measurementType: MeasurementType,
        weight: Double,
        reps: Int,
        durationSeconds: Int?,
        against bests: Bests,
        loadMode: LoadMode = .none,
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
            switch loadMode {
            case .none:
                if Double(reps) > bests.maxReps {
                    results.append(DetectedPR(type: .maxReps, value: Double(reps)))
                }
            case .weighted:
                // 荷重がある時のみ最大荷重を判定（0kg はただの自重なので拾わない）。
                if weight > 0, weight > bests.maxWeight {
                    results.append(DetectedPR(type: .maxWeight, value: weight))
                }
            case .assisted:
                // 補助は軽いほど強い。より小さい補助で挙げられたら PR（0=自重で挙げた最良）。
                if weight < bests.minAssist {
                    results.append(DetectedPR(type: .minAssist, value: weight))
                }
            }
        case .time:
            let secs = Double(durationSeconds ?? 0)
            guard secs > 0 else { return [] }
            if secs > bests.maxDuration {
                results.append(DetectedPR(type: .maxDuration, value: secs))
            }
        case .cardio:
            // 有酸素（距離・時間）は強度系 PR の対象外。記録は残すが PR 判定はしない。
            return []
        }
        return results
    }
}
