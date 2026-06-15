import Foundation

/// 推定 1RM 算出（§6.5）。純粋ロジックでユニットテスト対象。
enum OneRepMax {
    enum Formula: String, CaseIterable, Sendable {
        case epley
        case brzycki

        var label: String {
            switch self {
            case .epley: return "Epley"
            case .brzycki: return "Brzycki"
            }
        }
    }

    /// 推定 1RM（kg）。weight<=0 または reps<1 は 0 を返す。reps==1 は weight をそのまま返す。
    static func estimate(weight: Double, reps: Int, formula: Formula = .epley) -> Double {
        guard weight > 0, reps >= 1 else { return 0 }
        if reps == 1 { return weight }
        switch formula {
        case .epley:
            return weight * (1.0 + Double(reps) / 30.0)
        case .brzycki:
            // 37 - reps が 0 以下になる高レップ（reps>=37）は Epley にフォールバック。
            let denom = 37.0 - Double(reps)
            guard denom > 0 else { return weight * (1.0 + Double(reps) / 30.0) }
            return weight * 36.0 / denom
        }
    }
}
