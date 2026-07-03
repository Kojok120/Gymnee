import Foundation

/// セット表示の共有フォーマッタ。記録・履歴・ワークアウト詳細・種目詳細で共用する（重複排除）。
extension ExerciseSet {
    /// 計測タイプに応じたセット表示文字列。
    /// - time:      `"45秒"`（durationSeconds）
    /// - bodyweight: 符号付き（−=補助 / 0=自重 / ＋=加重）。`"自重 × 12"` / `"自重+10kg × 12"` / `"補助10kg × 12"`
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
        switch measurement {
        case .bodyweight:
            // 表示は符号で決まり loadMode に依存しない（同一種目で補助と加重を混在記録できる）。
            let mag = SetFormatting.weightString(abs(weight))
            if weight > 0 { return "自重+\(mag)kg × \(reps)" }
            if weight < 0 { return "補助\(mag)kg × \(reps)" }
            return "自重 × \(reps)"
        case .weight, .time, .cardio:
            return "\(SetFormatting.weightString(weight))kg × \(reps)"
        }
    }
}

enum SetFormatting {
    /// 重量の表記（整数は小数なし、端数は小数第1位）。
    static func weightString(_ weight: Double) -> String {
        weight == weight.rounded() ? String(Int(weight)) : String(format: "%.1f", weight)
    }
}
