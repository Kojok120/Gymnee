import Foundation
import SwiftData

/// 自分の公開投稿（`feed_items`）の作成・更新・削除。
///
/// 公開モデル（fail-closed / docs/identity-environment-design.md「公開面の設計」）:
/// - **feed_item が存在する＝公開済み。`visibility` がその公開範囲。**
/// - 新規作成はユーザーの明示操作だけ: 完了サマリーの「ソーシャルに投稿」（`publishWorkout`）、
///   チェックイン（`publishVisit`）、投稿メニューの公開範囲変更（`setVisibility`）。
/// - 定期同期（`syncPublishedPosts`）は**既存 feed_item の内容追従と、元データが消えた feed_item の
///   削除のみ**。未公開の記録から feed_item を勝手に作らない。これにより「マークを持たない端末
///   （2 台目・再インストール・pull 済み履歴）で過去記録が既定公開範囲で一括発行される」経路
///   （旧 `publishOwnPosts` の穴）を根絶する。
/// - 非恒久（ゲスト/匿名）アカウントは一切発行しない。
///
/// FeedItem.id == 元データ id（refId）。1 投稿 1 行。
enum FeedPublisher {

    /// feed_item に載せる 1 投稿分の内容（公開範囲以外）。
    private struct PostContent {
        let summary: String
        let date: Date
        let statsJSON: String?
    }

    // MARK: - 明示公開（作成/更新）

    /// 完了ワークアウトと、そのワークアウトで更新した最大重量 PR を指定 visibility で公開する。
    @MainActor
    static func publishWorkout(_ workout: Workout, authorName: String?, visibility: Visibility,
                               isPermanentAccount: Bool, context: ModelContext, sync: LocalSyncEngine) {
        guard isPermanentAccount, workout.completedAt != nil else { return }
        var pending: [PendingChange] = []
        upsert(refId: workout.id, userId: workout.userId, authorName: authorName, type: .workout,
               content: workoutContent(workout), visibility: visibility, context: context, pending: &pending)
        for pr in workoutMaxWeightPRs(workout) {
            upsert(refId: pr.id, userId: pr.userId, authorName: authorName, type: .pr,
                   content: prContent(pr, context: context), visibility: visibility, context: context, pending: &pending)
        }
        commit(pending, context: context, sync: sync)
    }

    /// 来店を指定 visibility で公開する（チェックイン）。
    @MainActor
    static func publishVisit(_ visit: Visit, authorName: String?, visibility: Visibility,
                             isPermanentAccount: Bool, context: ModelContext, sync: LocalSyncEngine) {
        guard isPermanentAccount else { return }
        var pending: [PendingChange] = []
        upsert(refId: visit.id, userId: visit.userId, authorName: authorName, type: .visit,
               content: visitContent(visit), visibility: visibility, context: context, pending: &pending)
        commit(pending, context: context, sync: sync)
    }

    /// 投稿メニューの公開範囲変更。private は「非公開に戻す」＝feed_item 削除（フォロワーから消える）、
    /// friends/public は既存 feed_item を更新（無ければ作成）する。
    @MainActor
    static func setVisibility(_ visibility: Visibility, forRefId refId: UUID, type: FeedItemType,
                             userId: UUID, authorName: String?, isPermanentAccount: Bool,
                             context: ModelContext, sync: LocalSyncEngine) {
        guard isPermanentAccount else { return }
        if visibility == .private { deleteFeedItem(forRefId: refId, context: context, sync: sync); return }
        guard let content = content(forRefId: refId, type: type, userId: userId, context: context) else { return }
        var pending: [PendingChange] = []
        upsert(refId: refId, userId: userId, authorName: authorName, type: type,
               content: content, visibility: visibility, context: context, pending: &pending)
        commit(pending, context: context, sync: sync)
    }

    // MARK: - 同期（更新/削除のみ・新規作成しない）

    /// 既存の自分の feed_item を最新の元データに追従させる（stats/summary の編集反映）。
    /// **新規作成も削除もしない**。ソーシャル表示・pull 後の整合に使う。
    /// - 新規作成しない: 未公開記録を公開しない（公開は明示操作のみ）。
    /// - 削除しない: 元データがまだ pull されていないだけの feed_item を消さない（2 台目・部分同期で
    ///   公開済み投稿を誤削除する事故の防止）。実際の削除は `deleteFeedItem`（元データ削除・非公開化）
    ///   とサーバーからの reconcile 伝播に一本化する。
    /// - PR 投稿は「発行時点の値のスナップショット」とし、非同意の後続セッションで更新された新 PR 値が
    ///   自動再公開されないよう内容追従の対象外にする。
    @MainActor
    static func syncPublishedPosts(userId: UUID, authorName: String?, context: ModelContext, sync: LocalSyncEngine) {
        let items = (try? context.fetch(FetchDescriptor<FeedItem>(predicate: #Predicate { $0.userId == userId }))) ?? []
        var pending: [PendingChange] = []
        for item in items {
            let type = item.type
            // PR はスナップショット。元データ未着（content=nil）でも消さず据え置く。
            guard type != .pr, let content = content(forRefId: item.refId, type: type, userId: userId, context: context) else { continue }
            if item.summary != content.summary || item.statsJSON != content.statsJSON || item.authorDisplayName != authorName {
                item.summary = content.summary
                item.statsJSON = content.statsJSON
                item.authorDisplayName = authorName
                item.updatedAt = .now
                item.isDirty = true
                pending.append(PendingChange(entity: "feed_items", recordId: item.id, operation: .upsert, updatedAt: item.updatedAt))
            }
        }
        commit(pending, context: context, sync: sync)
    }

    /// 元データ削除時・非公開化時に対応 feed_item を消す（ローカルに無くてもサーバー削除を積む）。
    @MainActor
    static func deleteFeedItem(forRefId refId: UUID, context: ModelContext, sync: LocalSyncEngine) {
        let rid = refId
        if let fi = (try? context.fetch(FetchDescriptor<FeedItem>(predicate: #Predicate { $0.id == rid })))?.first {
            context.delete(fi)
            try? context.save()
        }
        sync.enqueue(PendingChange(entity: "feed_items", recordId: refId, operation: .delete, updatedAt: .now))
    }

    // MARK: - 内部: upsert / commit

    @MainActor
    private static func upsert(refId: UUID, userId: UUID, authorName: String?, type: FeedItemType,
                              content: PostContent, visibility: Visibility,
                              context: ModelContext, pending: inout [PendingChange]) {
        let rid = refId
        if let item = (try? context.fetch(FetchDescriptor<FeedItem>(predicate: #Predicate { $0.id == rid })))?.first {
            guard item.visibilityRaw != visibility.rawValue || item.summary != content.summary
                    || item.statsJSON != content.statsJSON || item.authorDisplayName != authorName else { return }
            item.visibility = visibility
            item.summary = content.summary
            item.statsJSON = content.statsJSON
            item.authorDisplayName = authorName
            item.updatedAt = .now
            item.isDirty = true
            pending.append(PendingChange(entity: "feed_items", recordId: item.id, operation: .upsert, updatedAt: item.updatedAt))
        } else {
            let item = FeedItem(id: refId, userId: userId, authorDisplayName: authorName, type: type, refId: refId,
                                summary: content.summary, statsJSON: content.statsJSON, visibility: visibility, createdAt: content.date)
            context.insert(item)
            pending.append(PendingChange(entity: "feed_items", recordId: item.id, operation: .upsert, updatedAt: item.updatedAt))
        }
    }

    @MainActor
    private static func commit(_ pending: [PendingChange], context: ModelContext, sync: LocalSyncEngine) {
        guard !pending.isEmpty else { return }
        do {
            try context.save()
            sync.enqueueBatch(pending)
        } catch {
            // 保存失敗時は enqueue しない（次回の操作で再試行）。
        }
    }

    // MARK: - 内部: 元データ → PostContent

    /// refId + type から元データを引いて投稿内容を組む（元データが無ければ nil）。
    @MainActor
    private static func content(forRefId refId: UUID, type: FeedItemType, userId: UUID, context: ModelContext) -> PostContent? {
        let rid = refId
        switch type {
        case .visit:
            guard let v = (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.id == rid && $0.userId == userId })))?.first else { return nil }
            return visitContent(v)
        case .workout:
            guard let w = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == rid && $0.userId == userId })))?.first,
                  w.completedAt != nil else { return nil }
            return workoutContent(w)
        case .pr:
            guard let pr = (try? context.fetch(FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.id == rid && $0.userId == userId })))?.first else { return nil }
            return prContent(pr, context: context)
        }
    }

    @MainActor
    private static func visitContent(_ v: Visit) -> PostContent {
        let stats = v.photoURL.flatMap { FeedItemVisitStats(photoRef: $0).encodedJSON() }
        return PostContent(summary: v.gym?.name ?? "ジム活", date: v.visitedAt, statsJSON: stats)
    }

    @MainActor
    private static func workoutContent(_ w: Workout) -> PostContent {
        let allSets = w.exercises.flatMap(\.sets)
        let vol = allSets.reduce(0.0) { $0 + $1.volume }
        let totalVolume = vol.isFinite ? Int(vol) : 0
        let minutes = WorkoutDuration.minutes(date: w.date, completedAt: w.completedAt, durationSeconds: w.durationSeconds)
        let prCount = w.exercises.flatMap { $0.exercise?.personalRecords ?? [] }.filter { $0.workoutId == w.id }.count
        var seenMuscle = Set<MuscleGroup>()
        let muscles = w.exercises.compactMap { $0.exercise?.muscleGroup }.filter { seenMuscle.insert($0).inserted }.map(\.rawValue)
        let visibleExercises = w.exercises.filter { !$0.sets.isEmpty }
        let lines = visibleExercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { we in
                FeedItemStats.ExerciseLine(
                    name: we.exercise?.name ?? "種目",
                    sets: we.sets.sorted { $0.setIndex < $1.setIndex }.map { FeedItemStats.SetLine(text: $0.detailText, isPR: $0.isPR) }
                )
            }
        let stats = FeedItemStats(exercises: visibleExercises.count, sets: allSets.count, volume: totalVolume,
                                  minutes: minutes, prCount: prCount, muscles: muscles, exerciseLines: lines)
        return PostContent(summary: w.name, date: w.date, statsJSON: stats.encodedJSON())
    }

    /// PR 投稿の summary は「初回記録＝新しい種目に挑戦／更新＝自己ベスト更新」。初回判定は完了
    /// ワークアウトの日付から導出（PR.achievedAt は更新で上書きされ初回日を失うため）。
    @MainActor
    private static func prContent(_ pr: PersonalRecord, context: ModelContext) -> PostContent {
        let name = pr.exercise?.name ?? "種目"
        var isFirst = false
        if let exId = pr.exercise?.id {
            let cal = Calendar.current
            let days = pr.exercise?.workoutExercises.compactMap { we -> Date? in
                guard let w = we.workout, w.completedAt != nil, !we.sets.isEmpty else { return nil }
                return cal.startOfDay(for: w.date)
            } ?? []
            if let first = days.min() { isFirst = cal.isDate(pr.achievedAt, inSameDayAs: first) }
            _ = exId
        }
        let summary = isFirst ? "新しい種目に挑戦: \(name)" : "\(name) 自己ベスト更新"
        let stats = FeedItemPRStats(exercise: name, items: [FeedItemPRStats.Item(type: PRType.maxWeight.rawValue, value: pr.value)])
        return PostContent(summary: summary, date: pr.achievedAt, statsJSON: stats.encodedJSON())
    }

    /// このワークアウトで更新した最大重量 PR（feed に出すのは maxWeight のみ）。
    @MainActor
    private static func workoutMaxWeightPRs(_ workout: Workout) -> [PersonalRecord] {
        let wid = workout.id
        return workout.exercises.flatMap { we in
            (we.exercise?.personalRecords ?? []).filter { $0.workoutId == wid && $0.type == .maxWeight }
        }
    }
}
