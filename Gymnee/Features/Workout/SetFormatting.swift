import Foundation

/// セット表示の共有フォーマッタ。記録・履歴・ワークアウト詳細・種目詳細で共用する（重複排除）。
extension ExerciseSet {
    /// 計測タイプ（＋自重の荷重モード）に応じたセット表示文字列。
    /// - time:      `"45秒"`（durationSeconds）
    /// - bodyweight 自重のみ: `"自重 × 12"`
    /// - bodyweight 荷重:    `"自重+10kg × 12"`
    /// - bodyweight 補助:    `"補助10kg × 12"`
    /// - weight:    `"60kg × 10"`
    /// weight は整数なら小数を省く（記録カードの丸めに合わせる）。
    var detailText: String {
        let exercise = workoutExercise?.exercise
        let measurement = exercise?.measurementType ?? .weight
        if measurement == .time, let seconds = durationSeconds {
            return "\(seconds)秒"
        }
        if measurement == .cardio {
            let km = SetFormatting.weightString(distanceKm ?? 0)
            let mins = (durationSeconds ?? 0) / 60
            return "\(km)km · \(mins)分"
        }
        let w = SetFormatting.weightString(weight)
        switch measurement {
        case .bodyweight:
            switch exercise?.loadMode ?? .none {
            case .none:     return "自重 × \(reps)"
            case .weighted: return weight > 0 ? "自重+\(w)kg × \(reps)" : "自重 × \(reps)"
            case .assisted: return weight > 0 ? "補助\(w)kg × \(reps)" : "自重 × \(reps)"
            }
        case .weight, .time, .cardio:
            return "\(w)kg × \(reps)"
        }
    }
}

enum SetFormatting {
    /// 重量の表記（整数は小数なし、端数は小数第1位）。
    static func weightString(_ weight: Double) -> String {
        weight == weight.rounded() ? String(Int(weight)) : String(format: "%.1f", weight)
    }
}
