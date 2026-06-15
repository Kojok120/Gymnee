import Foundation

/// 補給ロギング → 在庫リマインド（§6.12）。消費ペースから残量と枯渇予測を出す。純粋ロジックでテスト対象。
enum SupplyAnalyzer {
    struct LogPoint: Sendable {
        let date: Date
        let amount: Double
    }

    struct Estimate: Equatable, Sendable {
        let consumedTotal: Double
        let dailyRate: Double
        let remaining: Double?
        let daysUntilEmpty: Double?
        let isLow: Bool
    }

    /// 残量・消費ペース・枯渇予測を算出する。
    /// - Parameters:
    ///   - logs: 補給ログ（日付・量）。
    ///   - servingsPerUnit: 1 容器あたりの回数（在庫換算に使用、nil なら残量計算なし）。
    ///   - unitsPurchased: 購入容器数（在庫の母数）。
    ///   - lowThresholdDays: 枯渇まで何日を切ったら「残りわずか」とみなすか。
    static func estimate(
        logs: [LogPoint],
        servingsPerUnit: Int?,
        unitsPurchased: Int,
        asOf reference: Date = .now,
        lowThresholdDays: Double = 7
    ) -> Estimate {
        let consumed = logs.reduce(0) { $0 + $1.amount }
        guard let first = logs.map(\.date).min() else {
            return Estimate(consumedTotal: 0, dailyRate: 0, remaining: nil, daysUntilEmpty: nil, isLow: false)
        }

        let days = max(reference.timeIntervalSince(first) / 86_400, 1)
        let rate = consumed / days

        var remaining: Double?
        if let servingsPerUnit, unitsPurchased > 0 {
            remaining = max(0, Double(servingsPerUnit * unitsPurchased) - consumed)
        }

        var daysUntilEmpty: Double?
        if let remaining, rate > 0 {
            daysUntilEmpty = remaining / rate
        }

        let isLow: Bool = {
            if let remaining, remaining <= 0 { return true }
            if let d = daysUntilEmpty { return d <= lowThresholdDays }
            return false
        }()

        return Estimate(consumedTotal: consumed, dailyRate: rate, remaining: remaining, daysUntilEmpty: daysUntilEmpty, isLow: isLow)
    }
}
