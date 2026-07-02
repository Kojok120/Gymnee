import Foundation
import SwiftData
import WidgetKit

/// SwiftData から共有スナップショットを再計算し、App Group へ保存して Widget を再読込する（§6.10）。
/// カレンダータブ表示のたびに呼ばれるため、取得は必要最小限（来店は日付列のみ・ワークアウトは各1件）に
/// 絞り、内容が前回と同じなら保存・Widget リロード・Watch 送信をスキップする。
@MainActor
enum SnapshotUpdater {
    static func update(userId: UUID, context: ModelContext) {
        // ストリーク計算に必要なのは来店日付だけ。リレーションや他列の実体化を避ける。
        var visitFetch = FetchDescriptor<Visit>(predicate: #Predicate { $0.userId == userId })
        visitFetch.propertiesToFetch = [\.visitedAt]
        let visitDays = ((try? context.fetch(visitFetch)) ?? []).map(\.visitedAt)
        let goal = UserDefaults.standard.object(forKey: "gymnee.weeklyGoal") as? Int ?? 3

        // 直近の完了ワークアウト（1件だけ取得）。
        var lastFetch = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.userId == userId && $0.completedAt != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        lastFetch.fetchLimit = 1
        let lastWorkout = (try? context.fetch(lastFetch))?.first

        // 次の予定ワークアウト（今日以降で最も近い1件だけ取得）。
        let now = Calendar.current.startOfDay(for: .now)
        var nextFetch = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.userId == userId && $0.isPlanned && $0.completedAt == nil && $0.date >= now },
            sortBy: [SortDescriptor(\.date)]
        )
        nextFetch.fetchLimit = 1
        let nextPlanned = (try? context.fetch(nextFetch))?.first

        var snapshot = GymneeSnapshot(
            streak: StreakCalculator.currentStreak(visitDays: visitDays),
            weeklyCount: StreakCalculator.weeklyVisitDays(visitDays: visitDays),
            weeklyGoal: goal,
            lastWorkoutName: lastWorkout?.name,
            lastWorkoutDate: lastWorkout?.date,
            nextPlannedName: nextPlanned?.name,
            nextPlannedDate: nextPlanned?.date,
            updatedAt: .now
        )
        // 内容が前回と同じなら何もしない（updatedAt の差は無視して比較）。
        // 全 Widget リロードと Watch 送信はコストが高く、無変化での実行は無駄なため。
        let previous = SharedStore.load()
        snapshot.updatedAt = previous.updatedAt
        if snapshot == previous { return }
        snapshot.updatedAt = .now

        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        // Apple Watch にも最新スナップショットを配布（端末間は App Group 不可のため WCSession 経由）。
        WatchConnector.shared.sendSnapshot(snapshot)
    }
}
