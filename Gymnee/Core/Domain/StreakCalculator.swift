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

    // MARK: - 週次ストリーク（⑥）
    // 筋トレは休息が正義のため「日次連続」は怪我/旅行/回復で簡単に折れて逆効果。
    // 「週 N 回（weeklyGoal）を達成した連続週数」を主指標にし、フリーズ（猶予週）で
    // 途切れの罪悪感を緩和する。純粋ロジックでユニットテスト対象。

    struct WeeklyStreak: Equatable, Sendable {
        /// 連続で目標達成した週数（今週は未達でも進行中として罰さない）。
        var weeks: Int
        /// 途切れを吸収したフリーズ（猶予週）の使用数。
        var freezesUsed: Int
        /// 今週は目標達成済みか。
        var metThisWeek: Bool
        /// 今週の来店「日数」。
        var visitsThisWeek: Int
        /// 適用した週次ゴール。
        var goal: Int
    }

    /// 週開始 → その週の distinct 来店日数を引く辞書を作る。
    private static func visitsPerWeek(_ visitDays: [Date], _ calendar: Calendar) -> [Date: Int] {
        var sets: [Date: Set<Date>] = [:]
        for d in visitDays {
            guard let ws = calendar.dateInterval(of: .weekOfYear, for: d)?.start else { continue }
            sets[ws, default: []].insert(calendar.startOfDay(for: d))
        }
        return sets.mapValues(\.count)
    }

    /// 現在の週次ストリーク。今週が未達なら進行中とみなし、先週から遡って数える。
    /// 目標未達の週は「1 ヶ月あたり freezesPerMonth 回」までフリーズ（猶予）として吸収し、
    /// その月のトークンを使い切った未達週で途切れる。空白の過去へ無駄に消費しないよう、
    /// 達成週の最古週より前には遡らない。
    static func currentWeeklyStreak(
        visitDays: [Date],
        weeklyGoal goal: Int,
        asOf reference: Date = .now,
        calendar: Calendar = .current,
        freezesPerMonth: Int = 1
    ) -> WeeklyStreak {
        guard goal > 0, let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: reference)?.start else {
            return WeeklyStreak(weeks: 0, freezesUsed: 0, metThisWeek: false, visitsThisWeek: 0, goal: max(goal, 0))
        }
        let perWeek = visitsPerWeek(visitDays, calendar)
        func met(_ ws: Date) -> Bool { (perWeek[ws] ?? 0) >= goal }
        // 達成週の最古週。これより前は遡らない（フリーズの空消費を防ぐ）。
        let earliestMet = perWeek.filter { $0.value >= goal }.keys.min()

        let visitsThisWeek = perWeek[thisWeekStart] ?? 0
        let metThisWeek = visitsThisWeek >= goal

        var weeks = metThisWeek ? 1 : 0
        var freezesUsed = 0
        var freezeUsedByMonth: [Int: Int] = [:]   // key=year*12+month → その月のフリーズ消費数
        // 今週が達成済みでも未達でも、評価は先週から過去方向へ（今週未達は進行中として罰さない）。
        guard var cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) else {
            return WeeklyStreak(weeks: weeks, freezesUsed: 0, metThisWeek: metThisWeek, visitsThisWeek: visitsThisWeek, goal: goal)
        }
        while let earliestMet, cursor >= earliestMet {
            if met(cursor) {
                weeks += 1
            } else {
                let mk = calendar.component(.year, from: cursor) * 12 + calendar.component(.month, from: cursor)
                if (freezeUsedByMonth[mk] ?? 0) < freezesPerMonth {
                    freezeUsedByMonth[mk, default: 0] += 1
                    freezesUsed += 1
                } else {
                    break
                }
            }
            guard let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return WeeklyStreak(weeks: weeks, freezesUsed: freezesUsed, metThisWeek: metThisWeek, visitsThisWeek: visitsThisWeek, goal: goal)
    }

    /// 過去最長の週次ストリーク（目標達成週の最長連続。フリーズは数えない）。
    static func longestWeeklyStreak(visitDays: [Date], weeklyGoal goal: Int, calendar: Calendar = .current) -> Int {
        guard goal > 0 else { return 0 }
        let perWeek = visitsPerWeek(visitDays, calendar)
        let metWeeks = perWeek.filter { $0.value >= goal }.keys.sorted()
        guard !metWeeks.isEmpty else { return 0 }
        var longest = 1, run = 1
        for i in 1..<metWeeks.count {
            if let expected = calendar.date(byAdding: .weekOfYear, value: 1, to: metWeeks[i - 1]),
               calendar.isDate(expected, equalTo: metWeeks[i], toGranularity: .weekOfYear) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
        }
        return longest
    }
}
