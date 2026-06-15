import Foundation

/// 連続記録・週次頻度ゴールの算出（§6.2）。純粋ロジックでユニットテスト対象。
enum StreakCalculator {

    /// 現在の連続来店日数。直近の来店が「今日」または「昨日」でなければ 0（連続が途切れたとみなす）。
    /// - Parameters:
    ///   - visitDays: 来店があった日（時刻は無視、startOfDay 前提でなくてよい）。
    ///   - asOf: 基準日（通常は今日）。
    static func currentStreak(visitDays: [Date], asOf reference: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set(visitDays.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: reference)
        var anchor = today
        if !days.contains(anchor) {
            // 今日が無ければ昨日から数える（今日はまだトレ前かもしれない）。
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  days.contains(yesterday) else { return 0 }
            anchor = yesterday
        }

        var count = 0
        var cursor = anchor
        while days.contains(cursor) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    /// 過去最長の連続来店日数。
    static func longestStreak(visitDays: [Date], calendar: Calendar = .current) -> Int {
        let sorted = Set(visitDays.map { calendar.startOfDay(for: $0) }).sorted()
        guard !sorted.isEmpty else { return 0 }

        var longest = 1
        var run = 1
        for i in 1..<sorted.count {
            if let expected = calendar.date(byAdding: .day, value: 1, to: sorted[i - 1]),
               calendar.isDate(expected, inSameDayAs: sorted[i]) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
        }
        return longest
    }

    /// 指定週（reference を含む週）の来店「日数」（同日複数来店は 1 と数える）。
    static func weeklyVisitDays(visitDays: [Date], in reference: Date = .now, calendar: Calendar = .current) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: reference) else { return 0 }
        let distinct = Set(
            visitDays
                .filter { week.contains($0) }
                .map { calendar.startOfDay(for: $0) }
        )
        return distinct.count
    }

    /// 週次ゴールに対する達成率（0.0〜1.0）。goal <= 0 のときは 0。
    static func weeklyAchievementRate(visitDays: [Date], goal: Int, in reference: Date = .now, calendar: Calendar = .current) -> Double {
        guard goal > 0 else { return 0 }
        let count = weeklyVisitDays(visitDays: visitDays, in: reference, calendar: calendar)
        return min(Double(count) / Double(goal), 1.0)
    }
}
