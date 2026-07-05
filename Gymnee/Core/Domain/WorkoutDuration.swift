import Foundation

/// ワークアウト総合時間の導出ルール（唯一の正）。
/// `Workout.durationSeconds`（完了時に確定した実経過、または手動で登録/修正した値）を優先し、
/// 無い場合のみ旧データ互換として date（開始）→ completedAt（完了）の経過から導出する。
///
/// 背景: 筋トレ後にまとめて記録すると「最初のセット記録→完了」の経過が実際の
/// トレーニング時間にならない（数分に潰れる）。過去日の後追い記録では逆に
/// 数時間〜数日に膨らむ。そのため経過をそのまま信頼せず、妥当な範囲だけを
/// ライブ記録として確定し、それ以外は未計測（nil）として手動入力に委ねる。
enum WorkoutDuration {
    /// ライブ記録とみなせる経過の上限（秒）。これを超える経過は
    /// 後追い記録・置き忘れセッション等の誤差として扱い、確定しない。
    static let maxLiveSeconds = 6 * 3600

    /// 完了時に確定する総合時間（秒）。妥当な経過（0 超〜上限以内）のみ返し、
    /// 過去日の後追い記録などは nil（未計測）のまま手動入力に委ねる。
    static func finalizedSeconds(date: Date, completedAt: Date) -> Int? {
        let interval = completedAt.timeIntervalSince(date)
        guard interval.isFinite, interval > 0, interval <= Double(maxLiveSeconds) else { return nil }
        return Int(interval)
    }

    /// 表示用の総合時間（分・最小 1 分）。nil は未計測（表示側は省略か「—」）。
    static func minutes(date: Date, completedAt: Date?, durationSeconds: Int?) -> Int? {
        if let secs = durationSeconds, secs > 0 { return max(1, secs / 60) }
        guard let end = completedAt, let secs = finalizedSeconds(date: date, completedAt: end) else { return nil }
        return max(1, secs / 60)
    }
}
