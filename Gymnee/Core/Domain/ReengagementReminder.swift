import Foundation

/// 記録が空いた利用者へ送るローカル通知の予約日を決める純粋ロジック。
enum ReengagementReminder {
    static let defaultInactivityDays = 3
    static let defaultReminderHour = 19
    static let defaultHorizonDays = 3
    static let hour = defaultReminderHour
    static let horizonDays = defaultHorizonDays

    static func identifierDate(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// 最終記録から指定日数後の夕方を起点に、未来の予約日を返す。
    /// 途中で記録された場合は呼び出し側が予約をすべて取り消す。
    static func scheduledDates(
        lastCompletedAt: Date?,
        now: Date = .now,
        calendar: Calendar = .current,
        inactivityDays: Int = defaultInactivityDays,
        reminderHour: Int = defaultReminderHour,
        horizonDays: Int = defaultHorizonDays
    ) -> [Date] {
        guard let lastCompletedAt,
              lastCompletedAt <= now,
              inactivityDays >= 1,
              (0...23).contains(reminderHour),
              horizonDays >= 1
        else { return [] }

        let lastDay = calendar.startOfDay(for: lastCompletedAt)
        guard let eligibleDay = calendar.date(byAdding: .day, value: inactivityDays, to: lastDay) else {
            return []
        }
        let today = calendar.startOfDay(for: now)
        var firstDay = max(eligibleDay, today)
        var firstComponents = calendar.dateComponents([.year, .month, .day], from: firstDay)
        firstComponents.hour = reminderHour
        firstComponents.minute = 0
        guard let firstFireDate = calendar.date(from: firstComponents) else { return [] }
        if firstFireDate <= now {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: firstDay) else { return [] }
            firstDay = nextDay
        }

        return (0..<horizonDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = reminderHour
            components.minute = 0
            return calendar.date(from: components)
        }
    }
}
