import Foundation

/// セット表示の共有フォーマッタ。記録・履歴・ワークアウト詳細・種目詳細で共用する（重複排除）。
extension ExerciseSet {
    /// 計測タイプに応じたセット表示文字列。
    /// - time:      `"45秒"`（durationSeconds）
    /// - bodyweight: 加重なし `"自重 × 12"` / 加重あり `"自重+10kg × 12"`
    /// - weight:    `"60kg × 10"`
    /// weight は整数なら小数を省く（記録カードの丸めに合わせる）。
    var detailText: String {
        let measurement = workoutExercise?.exercise?.measurementType ?? .weight
        if measurement == .time, let seconds = durationSeconds {
            return "\(seconds)秒"
        }
        let w = SetFormatting.weightString(weight)
        switch measurement {
        case .bodyweight:
            return weight > 0 ? "自重+\(w)kg × \(reps)" : "自重 × \(reps)"
        case .weight, .time:
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
