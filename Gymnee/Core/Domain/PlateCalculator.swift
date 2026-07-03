import Foundation

/// バーベルのプレート換算（合計重量 → 片側のプレート内訳）。純粋ロジックでテスト対象。
enum PlateCalculator {
    /// ジム標準のプレート（kg、片側1枚あたり・降順）。
    static let standardPlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    struct Breakdown: Equatable {
        /// 片側に載せるプレート（重い順）。空＝バーのみ。
        let perSide: [Double]
        /// プレートで作れない端数（合計 kg）。0 なら丸めなしで組める。
        let remainder: Double
    }

    /// 合計重量からバーを引いた片側分のプレート内訳を貪欲法で求める。
    /// 標準プレートは倍数関係にあるため貪欲法で最小枚数になる。target < bar は nil。
    static func breakdown(target: Double, bar: Double = 20, plates: [Double] = standardPlates) -> Breakdown? {
        guard target.isFinite, bar.isFinite, bar >= 0, target >= bar else { return nil }
        var remaining = (target - bar) / 2
        var perSide: [Double] = []
        for plate in plates.sorted(by: >) where plate > 0 {
            // 浮動小数の誤差で 1 枚分を取りこぼさないよう僅かに緩める。
            while remaining >= plate - 0.0001 {
                perSide.append(plate)
                remaining -= plate
            }
        }
        let remainder = max(0, (remaining * 2 * 100).rounded() / 100)
        return Breakdown(perSide: perSide, remainder: remainder)
    }
}
