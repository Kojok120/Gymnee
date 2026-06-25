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

        func upsert(refId: UUID, type: FeedItemType, summary: String, date: Date, statsJSON: String? = nil) {
            let vis = visibilityStore.visibility(for: refId) ?? defaultVisibility
            if let item = byRef.removeValue(forKey: refId) {
                guard item.visibilityRaw != vis.rawValue || item.summary != summary
                        || item.statsJSON != statsJSON || item.authorDisplayName != authorName else { return }
                item.visibility = vis
                item.summary = summary
                item.statsJSON = statsJSON
                item.authorDisplayName = authorName
                item.updatedAt = .now
                item.isDirty = true
                sync.enqueue(PendingChange(entity: "feed_items", recordId: item.id, operation: .upsert, updatedAt: item.updatedAt))
                changed = true
            } else {
                // 同 id(=refId) の FeedItem が既に存在する場合の unique 衝突insertを避ける（保険）。
                let rid = refId
                if (try? context.fetch(FetchDescriptor<FeedItem>(predicate: #Predicate { $0.id == rid })))?.first != nil {
                    return
                }
                let item = FeedItem(id: refId, userId: userId, authorDisplayName: authorName, type: type, refId: refId, summary: summary, statsJSON: statsJSON, visibility: vis, createdAt: date)
                context.insert(item)
                sync.enqueue(PendingChange(entity: "feed_items", recordId: item.id, operation: .upsert, updatedAt: item.updatedAt))
                changed = true
            }
        }

        for v in visits {
            upsert(refId: v.id, type: .visit, summary: v.gym?.name ?? "チェックイン", date: v.visitedAt)
        }
        for w in workouts {
            // サマリは種目名のみ（数値は stats_json が運ぶ）。フォロワー側もリッチカードを描ける。
            let allSets = w.exercises.flatMap(\.sets)
            let vol = allSets.reduce(0.0) { $0 + $1.volume }
            let totalVolume = vol.isFinite ? Int(vol) : 0
            let minutes = w.completedAt.map { max(1, Int($0.timeIntervalSince(w.date) / 60)) }
            let prCount = prs.filter { $0.workoutId == w.id }.count
            var seenMuscle = Set<MuscleGroup>()
            let muscles = w.exercises.compactMap { $0.exercise?.muscleGroup }.filter { seenMuscle.insert($0).inserted }.map(\.rawValue)
            let stats = FeedItemStats(exercises: w.exercises.count, sets: allSets.count, volume: totalVolume,
                                      minutes: minutes, prCount: prCount, muscles: muscles)
            upsert(refId: w.id, type: .workout, summary: w.name, date: w.date, statsJSON: stats.encodedJSON())
        }
        // PR はフィードを荒らさないよう「種目 × 日」で 1 件に集約する。初回の種目は
        // 最大重量/レップ…と乱発せず「新しい種目に挑戦」1件、以降は「自己ベスト更新」1件。
        let cal = Calendar.current
        var firstDayByExercise: [UUID: Date] = [:]
        for pr in prs {
            guard let exId = pr.exercise?.id else { continue }
            let day = cal.startOfDay(for: pr.achievedAt)
            if let cur = firstDayByExercise[exId] { firstDayByExercise[exId] = min(cur, day) }
            else { firstDayByExercise[exId] = day }
        }
        let prGroups = Dictionary(grouping: prs.filter { $0.exercise != nil }) { pr in
            "\(pr.exercise!.id.uuidString)|\(cal.startOfDay(for: pr.achievedAt).timeIntervalSince1970)"
        }
        for group in prGroups.values {
            guard let rep = group.max(by: { $0.value < $1.value }), let exId = rep.exercise?.id else { continue }
            let name = rep.exercise?.name ?? "種目"
            let isFirst = cal.startOfDay(for: rep.achievedAt) == firstDayByExercise[exId]
            let summary = isFirst ? "新しい種目に挑戦: \(name)" : "\(name) 自己ベスト更新"
            upsert(refId: rep.id, type: .pr, summary: summary, date: rep.achievedAt)
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
