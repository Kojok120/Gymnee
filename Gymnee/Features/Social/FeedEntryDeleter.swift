import Foundation
import SwiftData

/// フィード項目の削除。**元データ（workout / personal_record）ごと消す**。
///
/// 「非公開にする」（`FeedPublisher.setVisibility(.private)` ＝ feed_item だけ削除）とは別物で、
/// こちらは記録そのものが消える＝カレンダーや分析からも無くなる不可逆操作。呼び出し側で必ず確認を取る。
///
/// 自分の投稿一覧（`MyPostsView`）とソーシャルフィード（`SocialFeedView`）の両方から使うので、
/// 片方だけ直して挙動がずれないようここに集約する。
@MainActor
enum FeedEntryDeleter {

    /// - Parameters:
    ///   - workouts / prs: 画面側の `@Query` 結果（entry.id から実体を引くため）。
    static func delete(_ entry: FeedEntry,
                       workouts: [Workout],
                       prs: [PersonalRecord],
                       context: ModelContext,
                       sync: LocalSyncEngine) {
        switch entry.kind {
        case .pr:
            guard let pr = prs.first(where: { $0.id == entry.id }) else { return }
            context.delete(pr)
            try? context.save()
            sync.enqueue(PendingChange(entity: "personal_records", recordId: entry.id, operation: .delete, updatedAt: .now))
            // 元データが消えたので、公開済みなら対応 feed_item も削除して同期整合させる。
            FeedPublisher.deleteFeedItem(forRefId: entry.id, context: context, sync: sync)
        case .workout:
            guard let w = workouts.first(where: { $0.id == entry.id }) else { return }
            PhotoStore.delete(w.localPhotoFilename)
            context.delete(w)
            try? context.save()
            sync.enqueue(PendingChange(entity: "workouts", recordId: entry.id, operation: .delete, updatedAt: .now))
            FeedPublisher.deleteFeedItem(forRefId: entry.id, context: context, sync: sync)
        }
    }
}
