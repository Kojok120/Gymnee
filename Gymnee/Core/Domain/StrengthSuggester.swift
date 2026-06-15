import Foundation

/// %1RM ベースの重量提案（§6.5 深掘り）。純粋ロジックでテスト対象。
enum StrengthSuggester {
    /// 推定 1RM から、目標レップ数をこなせる作業重量を逆算（Epley 逆算）して丸める。
    static func workingWeight(e1RM: Double, reps: Int, increment: Double = 2.5) -> Double {
        guard e1RM > 0, reps >= 1 else { return 0 }
        if reps == 1 { return roundTo(e1RM, increment: increment) }
        let raw = e1RM / (1.0 + Double(reps) / 30.0)
        return roundTo(raw, increment: increment)
    }

    /// 重量×レップが推定1RMに対して占める割合（0.0〜）。e1RM<=0 は 0。
    static func percentOfMax(weight: Double, e1RM: Double) -> Double {
        guard e1RM > 0 else { return 0 }
        return weight / e1RM
    }

    /// 目標レップ帯（例: 5/8/12）の推奨重量一覧。
    static func suggestions(e1RM: Double, reps: [Int] = [5, 8, 12], increment: Double = 2.5) -> [(reps: Int, weight: Double)] {
        reps.map { ($0, workingWeight(e1RM: e1RM, reps: $0, increment: increment)) }
    }

    private static func roundTo(_ value: Double, increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }
}
