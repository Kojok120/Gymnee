import Foundation

/// プレート計算機（§6.5）。目標重量に対する片側プレート構成を提示する。純粋ロジックでテスト対象。
enum PlateCalculator {
    /// 標準的な kg プレート（重い順）。
    static let standardPlatesKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    struct PlateCount: Equatable, Sendable, Identifiable {
        let plate: Double
        let count: Int
        var id: Double { plate }
    }

    struct Result: Equatable, Sendable {
        /// 片側のプレート構成（重い順）。
        let perSide: [PlateCount]
        /// 表現しきれなかった片側の余り（kg）。0 なら目標ぴったり。
        let remainderPerSide: Double
        /// 目標が達成可能か（バー重量以上 かつ 余りが極小）。
        var isExact: Bool { remainderPerSide < 0.0001 }
    }

    /// 目標重量に対する片側プレート構成を貪欲法で計算する。
    /// - Parameters:
    ///   - target: 目標総重量（kg）。
    ///   - bar: バー重量（kg、既定 20）。
    ///   - plates: 利用可能プレート（重い順でなくてもよい）。
    static func compute(target: Double, bar: Double = 20, plates: [Double] = standardPlatesKg) -> Result {
        guard target >= bar else {
            return Result(perSide: [], remainderPerSide: max(0, (bar - target) / 2))
        }
        var perSide = (target - bar) / 2.0
        let sorted = plates.sorted(by: >)
        var counts: [PlateCount] = []
        for plate in sorted where plate > 0 {
            let n = Int((perSide / plate).rounded(.down) + 1e-9)
            if n > 0 {
                counts.append(PlateCount(plate: plate, count: n))
                perSide -= Double(n) * plate
            }
        }
        // 浮動小数の誤差を丸める。
        let remainder = perSide < 1e-6 ? 0 : perSide
        return Result(perSide: counts, remainderPerSide: remainder)
    }
}
