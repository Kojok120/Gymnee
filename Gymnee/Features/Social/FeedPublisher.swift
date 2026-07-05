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
        // enqueue は呼ぶたびに outbox 全書き出し(persist)が走るため、発行分はここに溜めて末尾で1回 batch する。
        var pending: [PendingChange] = []

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
                pending.append(PendingChange(entity: "feed_items", recordId: item.id, operation: .upsert, updatedAt: item.updatedAt))
                changed = true
            } else {
                // 同 id(=refId) の FeedItem が既に存在する場合の unique 衝突insertを避ける（保険）。
                let rid = refId
                if (try? context.fetch(FetchDescriptor<FeedItem>(predicate: #Predicate { $0.id == rid })))?.first != nil {
                    return
                }
                let item = FeedItem(id: refId, userId: userId, authorDisplayName: authorName, type: type, refId: refId, summary: summary, statsJSON: statsJSON, visibility: vis, createdAt: date)
                context.insert(item)
                pending.append(PendingChange(entity: "feed_items", recordId: item.id, operation: .upsert, updatedAt: item.updatedAt))
                changed = true
            }
        }

        // ワークアウトごとの PR 件数を先に索引化（毎回 prs を全走査する N+1 を避ける）。
        var prCountByWorkout: [UUID: Int] = [:]
        for pr in prs { if let wid = pr.workoutId { prCountByWorkout[wid, default: 0] += 1 } }

        for v in visits {
            // 写真をリモートに上げてある来店は参照を載せ、フォロワー側でも写真を表示できるようにする。
            let visitStats = v.photoURL.flatMap { FeedItemVisitStats(photoRef: $0).encodedJSON() }
            upsert(refId: v.id, type: .visit, summary: v.gym?.name ?? "チェックイン", date: v.visitedAt, statsJSON: visitStats)
        }
        for w in workouts {
            // サマリは種目名のみ（数値は stats_json が運ぶ）。フォロワー側もリッチカードを描ける。
            let allSets = w.exercises.flatMap(\.sets)
            let vol = allSets.reduce(0.0) { $0 + $1.volume }
            let totalVolume = vol.isFinite ? Int(vol) : 0
            let minutes = WorkoutDuration.minutes(date: w.date, completedAt: w.completedAt, durationSeconds: w.durationSeconds)
            let prCount = prCountByWorkout[w.id] ?? 0
            var seenMuscle = Set<MuscleGroup>()
            let muscles = w.exercises.compactMap { $0.exercise?.muscleGroup }.filter { seenMuscle.insert($0).inserted }.map(\.rawValue)
            // 種目別セット内訳（他人の投稿でも「メニュー」を再現するため）。空種目は出さない。
            let visibleExercises = w.exercises.filter { !$0.sets.isEmpty }
            let lines = visibleExercises
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { we in
                    FeedItemStats.ExerciseLine(
                        name: we.exercise?.name ?? "種目",
                        sets: we.sets.sorted { $0.setIndex < $1.setIndex }
                            .map { FeedItemStats.SetLine(text: $0.detailText, isPR: $0.isPR) }
                    )
                }
            // 「種目」件数は内訳(lines)と一致させる（空種目を数に含めない）。
            let stats = FeedItemStats(exercises: visibleExercises.count, sets: allSets.count, volume: totalVolume,
                                      minutes: minutes, prCount: prCount, muscles: muscles, exerciseLines: lines)
            upsert(refId: w.id, type: .workout, summary: w.name, date: w.date, statsJSON: stats.encodedJSON())
        }
        // 自己ベストは「最大重量」の更新だけをフィードに投稿する。推定1RM/最大レップ/最長時間/最小補助
        // などその他のトロフィーはフィードに出さず、各セットの記録内（ワークアウト詳細のトロフィー表示）に
        // 内包する。最大重量 PR は種目ごとに 1 行を上書き保持するため、種目ごとに 1 投稿へ自然にまとまる。
        let cal = Calendar.current
        // 種目ごとの「初めて記録した日」（完了ワークアウト基準）。PR の achievedAt は更新のたびに
        // 上書きされ初回日を失うため、初回判定はワークアウトの日付から導出する。
        var firstWorkoutDay: [UUID: Date] = [:]
        for w in workouts {
            let day = cal.startOfDay(for: w.date)
            for we in w.exercises where !we.sets.isEmpty {
                guard let exId = we.exercise?.id else { continue }
                if let cur = firstWorkoutDay[exId] { firstWorkoutDay[exId] = min(cur, day) }
                else { firstWorkoutDay[exId] = day }
            }
        }
        for pr in prs where pr.type == .maxWeight {
            guard let exId = pr.exercise?.id else { continue }
            let name = pr.exercise?.name ?? "種目"
            // 現在の最大重量が種目の初回記録日のままなら「新しい種目に挑戦」、更新後は「自己ベスト更新」。
            let isFirst = firstWorkoutDay[exId].map { cal.isDate(pr.achievedAt, inSameDayAs: $0) } ?? false
            let summary = isFirst ? "新しい種目に挑戦: \(name)" : "\(name) 自己ベスト更新"
            let prStats = FeedItemPRStats(
                exercise: name,
                items: [FeedItemPRStats.Item(type: PRType.maxWeight.rawValue, value: pr.value)]
            )
            upsert(refId: pr.id, type: .pr, summary: summary, date: pr.achievedAt, statsJSON: prStats.encodedJSON())
        }

        // 残った既存 = もう存在しない投稿 → feed_item を削除して同期。
        for stale in byRef.values {
            let id = stale.id
            context.delete(stale)
            pending.append(PendingChange(entity: "feed_items", recordId: id, operation: .delete, updatedAt: .now))
            changed = true
        }

        guard changed else { return }
        do {
            try context.save()
            // 保存成功時だけ同期キューへ積む（保存できなかった変更を push してローカルと乖離させない）。
            if !pending.isEmpty { sync.enqueueBatch(pending) }
        } catch {
            // 保存失敗時は enqueue しない（次回の発行で再試行）。
        }
    }

    /// 来店/ワークアウト削除時に、対応する feed_item（id == 元データ id）も削除して同期する。
    /// これによりフォロワーのフィードからも消える（feed_items は reconcile 対象なので削除が伝播する）。
    /// 注: PR は feed_item を種目×日でグルーピングするため対象外（publishOwnPosts の再発行に委ねる）。
    @MainActor
    static func deleteFeedItem(forRefId refId: UUID, context: ModelContext, sync: LocalSyncEngine) {
        let rid = refId
        if let fi = (try? context.fetch(FetchDescriptor<FeedItem>(predicate: #Predicate { $0.id == rid })))?.first {
            context.delete(fi)
            try? context.save()
        }
        // ローカルに feed_item が無くても、サーバー側を確実に消すため delete を積む。
        sync.enqueue(PendingChange(entity: "feed_items", recordId: refId, operation: .delete, updatedAt: .now))
    }
}
