import Foundation

/// ウォームアップのランプセット生成（§6.5 深掘り）。純粋ロジックでテスト対象。
/// 本番重量に向けてバー→40%→60%→80% と漸増するセットを提案する。
enum WarmupCalculator {
    struct WarmupSet: Equatable, Sendable {
        let weight: Double
        let reps: Int
    }

    /// 標準的なウォームアップ比率とレップ（重い順に本番へ近づく）。
    private static let scheme: [(pct: Double, reps: Int)] = [
        (0.40, 5), (0.60, 3), (0.80, 2),
    ]

    /// 本番重量に対するウォームアップセット列を返す。
    /// - Parameters:
    ///   - workingWeight: 本番（メイン）重量。
    ///   - bar: バー重量（既定 20）。
    ///   - increment: 丸め単位（既定 2.5kg）。
    static func sets(workingWeight: Double, bar: Double = 20, increment: Double = 2.5) -> [WarmupSet] {
        guard workingWeight > bar else { return [] }

        var result: [WarmupSet] = [WarmupSet(weight: bar, reps: 8)]
        for step in scheme {
            let raw = workingWeight * step.pct
            let rounded = roundTo(raw, increment: increment)
            // バー超〜本番未満、かつ直前より重い場合のみ採用（重複・逆行を除外）。
            if rounded > (result.last?.weight ?? bar), rounded < workingWeight {
                result.append(WarmupSet(weight: rounded, reps: step.reps))
            }
        }
        return result
    }

    private static func roundTo(_ value: Double, increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }
}
