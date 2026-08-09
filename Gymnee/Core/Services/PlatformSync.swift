import Foundation
import SwiftData

/// Widget スナップショット更新＋ローカル通知の予約（§6.10）をまとめて行う。
///
/// もとはカレンダー画面の `.task` だけが呼んでいたが、カレンダーをタブから「その他」配下へ
/// 移した結果その画面を開く頻度が落ちるため、画面に依存しない場所（起動時のルート）からも
/// 実行できるようここへ切り出した。純粋なロジック（連続日数の算出）は `StreakCalculator` に任せる。
@MainActor
enum PlatformSync {

    /// 起動時・記録の増減時に呼ぶ。ワークアウトは自前で取り直す（呼び出し側の @Query に依存しない）。
    static func run(userId: UUID, context: ModelContext, notifications: NotificationService, calendar: Calendar = .current) {
        SnapshotUpdater.update(userId: userId, context: context)
        let workouts = (try? context.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.userId == userId })
        )) ?? []
        scheduleReminders(workouts: workouts, notifications: notifications, calendar: calendar)
    }

    /// 既にワークアウトを持っている画面（カレンダー）から呼ぶ版。
    static func run(userId: UUID, context: ModelContext, workouts: [Workout], notifications: NotificationService, calendar: Calendar = .current) {
        SnapshotUpdater.update(userId: userId, context: context)
        scheduleReminders(workouts: workouts, notifications: notifications, calendar: calendar)
    }

    /// 連続記録の途切れ予告・週次まとめ・予定ワークアウトの通知を予約し直す。
    static func scheduleReminders(workouts: [Workout], notifications: NotificationService, calendar: Calendar = .current) {
        let activeDays = workouts.filter { $0.completedAt != nil }.map { $0.completedAt ?? $0.date }
        let streak = StreakCalculator.currentStreak(activeDays: activeDays, calendar: calendar)
        let activeToday = activeDays.contains { calendar.isDateInToday($0) }
        notifications.scheduleStreakReminder(streak: streak, hasRecordedToday: activeToday)
        notifications.scheduleWeeklyRecap()

        let today = calendar.startOfDay(for: .now)
        let planned = workouts
            .filter { $0.isPlanned && $0.completedAt == nil && $0.date >= today }
            .map { (id: $0.id, name: $0.name, date: $0.date) }
        notifications.schedulePlannedWorkouts(planned)
    }
}
