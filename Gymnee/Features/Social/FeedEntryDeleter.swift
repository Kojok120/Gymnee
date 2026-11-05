import Foundation
import SwiftData

/// フィード項目の削除。**元データ（workout / personal_record）ごと消す**。
///
/// 「非公開にする」（`FeedPublisher.setVisibility(.private)` ＝ feed_item だけ削除）とは別物で、
/// こちらは記録そのものが消える＝カレンダーや分析からも無くなる不可逆操作。必ず `request` の確認を通す（#168）。
///
/// 自分の投稿一覧（`MyPostsView`）とソーシャルフィード（`SocialFeedView`）の両方から使うので、
/// 片方だけ直して挙動がずれないようここに集約する。ワークアウトの削除そのものは `WorkoutDeleter` に寄せる。
@MainActor
enum FeedEntryDeleter {

    /// 消せたら true。保存に失敗したらサーバーには何も送らない。
    /// - Parameters:
    ///   - workouts / prs: 画面側の `@Query` 結果（entry.id から実体を引くため）。
    @discardableResult
    static func delete(_ entry: FeedEntry,
                       workouts: [Workout],
                       prs: [PersonalRecord],
                       context: ModelContext,
                       sync: LocalSyncEngine) -> Bool {
        switch entry.kind {
        case .pr:
            guard let pr = prs.first(where: { $0.id == entry.id }) else { return false }
            context.delete(pr)
            do {
                try context.save()
            } catch {
                context.rollback()
                return false
            }
            sync.enqueue(PendingChange(entity: "personal_records", recordId: entry.id, operation: .delete, updatedAt: .now))
            // 元データが消えたので、公開済みなら対応 feed_item も削除して同期整合させる。
            FeedPublisher.deleteFeedItem(forRefId: entry.id, context: context, sync: sync)
            return true
        case .workout:
            guard let w = workouts.first(where: { $0.id == entry.id }) else { return false }
            return WorkoutDeleter.delete(w, context: context, sync: sync)
        }
    }

    /// 削除の確認（消える中身を数で書く。公開済みなら「非公開にする」も出す）。
    static func request(_ entry: FeedEntry,
                        workouts: [Workout],
                        prs: [PersonalRecord],
                        author: WorkoutDeleter.Author,
                        context: ModelContext,
                        sync: LocalSyncEngine,
                        onFailure: @escaping @MainActor () -> Void = {},
                        onDone: @escaping @MainActor () -> Void = {}) -> DeletionRequest? {
        switch entry.kind {
        case .workout:
            guard let w = workouts.first(where: { $0.id == entry.id }) else { return nil }
            return WorkoutDeleter.request(for: w, author: author, context: context, sync: sync, onFailure: onFailure, onDone: onDone)
        case .pr:
            let refId = entry.id
            let type = entry.feedItemType
            var makePrivate: (@MainActor () -> Void)?
            if entry.isPublished {
                makePrivate = {
                    FeedPublisher.setVisibility(.private, forRefId: refId, type: type, userId: author.userId,
                                                authorName: author.name, isPermanentAccount: author.isPermanentAccount,
                                                context: context, sync: sync)
                    Task { await sync.syncNow(force: true) }
                    onDone()
                }
            }
            let onDelete: @MainActor () -> Void = {
                if delete(entry, workouts: workouts, prs: prs, context: context, sync: sync) { onDone() } else { onFailure() }
            }
            return DeletionRequest(
                title: DeletionCopy.prTitle,
                message: DeletionCopy.prMessage(isPublished: entry.isPublished),
                onDelete: onDelete,
                makePrivate: makePrivate
            )
        }
    }
}
