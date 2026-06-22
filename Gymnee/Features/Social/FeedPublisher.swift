import Foundation
import SwiftData

/// 自分の投稿（来店／完了ワークアウト／自己ベスト）を `feed_items` として発行・更新・削除し、
/// 同期キューへ積む（§6.11）。フォロワーはサーバー（RLS=本人＋public＋friends&フォロー）から
/// 取り込み、共有フィードに表示する。公開範囲は端末ローカルの PostVisibilityStore を反映する。
///
/// FeedItem.id は元投稿の id（refId）と同じにして 1 投稿 1 行に保つ。
enum FeedPublisher {
    @MainActor
    static func publishOwnPosts(
        userId: UUID,
        authorName: String?,
        context: ModelContext,
        visibilityStore: PostVisibilityStore,
        defaultVisibility: Visibility,
        sync: LocalSyncEngine
    ) {
        let visits = (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.userId == userId }))) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.userId == userId && $0.completedAt != nil }))) ?? []
        let prs = (try? context.fetch(FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.userId == userId }))) ?? []
        let existing = (try? context.fetch(FetchDescriptor<FeedItem>(predicate: #Predicate { $0.userId == userId }))) ?? []

        var byRef: [UUID: FeedItem] = [:]
        for item in existing { byRef[item.refId] = item }
        var changed = false

        func upsert(refId: UUID, type: FeedItemType, summary: String, date: Date) {
            let vis = visibilityStore.visibility(for: refId) ?? defaultVisibility
            if let item = byRef.removeValue(forKey: refId) {
                guard item.visibilityRaw != vis.rawValue || item.summary != summary || item.authorDisplayName != authorName else { return }
                item.visibility = vis
                item.summary = summary
                item.authorDisplayName = authorName
                item.updatedAt = .now
                item.isDirty = true
                sync.enqueue(PendingChange(entity: "feed_items", recordId: item.id, operation: .upsert, updatedAt: item.updatedAt))
                changed = true
            } else {
                let item = FeedItem(id: refId, userId: userId, authorDisplayName: authorName, type: type, refId: refId, summary: summary, visibility: vis, createdAt: date)
                context.insert(item)
                sync.enqueue(PendingChange(entity: "feed_items", recordId: item.id, operation: .upsert, updatedAt: item.updatedAt))
                changed = true
            }
        }

        for v in visits {
            upsert(refId: v.id, type: .visit, summary: v.gym?.name ?? "チェックイン", date: v.visitedAt)
        }
        for w in workouts {
            let sets = w.exercises.reduce(0) { $0 + $1.sets.count }
            upsert(refId: w.id, type: .workout, summary: "\(w.name)・\(w.exercises.count)種目・\(sets)セット", date: w.date)
        }
        for pr in prs {
            upsert(refId: pr.id, type: .pr, summary: "\(pr.exercise?.name ?? "種目") \(pr.type.label)", date: pr.achievedAt)
        }

        // 残った既存 = もう存在しない投稿 → feed_item を削除して同期。
        for stale in byRef.values {
            let id = stale.id
            context.delete(stale)
            sync.enqueue(PendingChange(entity: "feed_items", recordId: id, operation: .delete, updatedAt: .now))
            changed = true
        }

        if changed { try? context.save() }
    }
}
