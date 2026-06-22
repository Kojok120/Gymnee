import Foundation
import SwiftData
import WidgetKit

/// SwiftData から共有スナップショットを再計算し、App Group へ保存して Widget を再読込する（§6.10）。
@MainActor
enum SnapshotUpdater {
    static func update(userId: UUID, context: ModelContext) {
        let visits = (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.userId == userId }))) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.userId == userId }))) ?? []
        let goal = UserDefaults.standard.object(forKey: "gymnee.weeklyGoal") as? Int ?? 3

        let visitDays = visits.map(\.visitedAt)
        let lastWorkout = workouts.filter { $0.completedAt != nil }.max { $0.date < $1.date }
        let now = Calendar.current.startOfDay(for: .now)
        let nextPlanned = workouts
            .filter { $0.isPlanned && $0.completedAt == nil && $0.date >= now }
            .min { $0.date < $1.date }

        let snapshot = GymneeSnapshot(
            streak: StreakCalculator.currentStreak(visitDays: visitDays),
            weeklyCount: StreakCalculator.weeklyVisitDays(visitDays: visitDays),
            weeklyGoal: goal,
            lastWorkoutName: lastWorkout?.name,
            lastWorkoutDate: lastWorkout?.date,
            nextPlannedName: nextPlanned?.name,
            nextPlannedDate: nextPlanned?.date,
            updatedAt: .now
        )
        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        // Apple Watch にも最新スナップショットを配布（端末間は App Group 不可のため WCSession 経由）。
        WatchConnector.shared.sendSnapshot(snapshot)
    }
}
