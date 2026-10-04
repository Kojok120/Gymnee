import Foundation
import SwiftData

/// はじめてのメニュー（`StarterMenu`）を今日の計画として保存する（issue #119）。
/// 記録画面は今日の未消化の計画を先頭タブに出すので、保存後に記録を開けばそのメニューで始まる。
enum StarterPlanner {
    /// 選んだメニューで今日の計画を作る。以前にはじめてのメニューから作った今日の未消化の計画は
    /// 置き換える（選び直し）。ユーザーが自分で入れた計画には触れない。
    @MainActor
    @discardableResult
    static func apply(
        _ menu: StarterMenu.Menu,
        userId: UUID,
        context: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> PlannedWorkout {
        let today = calendar.startOfDay(for: now)
        let marker = StarterMenu.planNote
        let existing = (try? context.fetch(
            FetchDescriptor<PlannedWorkout>(predicate: #Predicate {
                $0.userId == userId && !$0.isDone && $0.note == marker
            })
        )) ?? []
        for plan in existing where calendar.isDate(plan.date, inSameDayAs: today) {
            context.delete(plan)
        }

        let plan = PlannedWorkout(userId: userId, date: today, title: menu.title, note: marker)
        plan.detailJSON = StarterMenu.detailJSON(for: menu)
        context.insert(plan)
        try? context.save()
        return plan
    }

    /// 完了したワークアウトの件数（開始ゲートで、はじめてのメニューを出すかの判定に使う）。
    @MainActor
    static func completedWorkoutCount(userId: UUID, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate {
            $0.userId == userId && $0.completedAt != nil
        })
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
