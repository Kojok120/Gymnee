import SwiftUI
import SwiftData

/// 投稿カード下のいいねバー（§6.11）。feed_item 単位でいいねを集計・トグルする。
/// パフォーマンス: 行ごとに @Query を張らず、親が PostReaction を一括取得して該当分を渡す。
/// タップ範囲は見た目を変えずに余白＋contentShape で拡大し、押しやすくする。
struct ReactionBar: View {
    let feedItemId: UUID
    let userId: UUID
    /// この feed_item に紐づくリアクション（親が一括取得して渡す）。
    let reactions: [PostReaction]

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync

    private var mine: PostReaction? {
        reactions.first { $0.userId == userId && $0.kindRaw == ReactionKind.like.rawValue }
    }
    private var liked: Bool { mine != nil }
    private var count: Int { reactions.filter { $0.kindRaw == ReactionKind.like.rawValue }.count }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button { toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .symbolEffect(.bounce, value: liked)
                    if count > 0 { Text("\(count)").font(.caption.monospacedDigit()) }
                }
                .font(.subheadline)
                .foregroundStyle(liked ? Theme.energy : Color.secondary)
                // 見た目は据え置きで当たり判定だけ拡大（場所は取らない）。
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .sensoryFeedback(.impact(weight: .light), trigger: liked)
    }

    private func toggle() {
        ReactionActions.toggleLike(feedItemId: feedItemId, userId: userId, existing: mine, context: context, sync: sync)
    }
}

/// いいね操作の共有ロジック（ReactionBar とフィードのダブルタップから利用）。
enum ReactionActions {
    /// いいねのトグル（無ければ追加・あれば取り消し）。
    @MainActor static func toggleLike(feedItemId: UUID, userId: UUID, existing: PostReaction?, context: ModelContext, sync: LocalSyncEngine) {
        if let existing {
            let id = existing.id
            context.delete(existing)
            try? context.save()
            sync.enqueue(PendingChange(entity: "post_reactions", recordId: id, operation: .delete, updatedAt: .now))
        } else {
            let r = PostReaction(userId: userId, feedItemId: feedItemId, kind: .like)
            context.insert(r)
            try? context.save()
            sync.enqueue(PendingChange(entity: "post_reactions", recordId: r.id, operation: .upsert, updatedAt: r.updatedAt))
        }
    }

    /// いいねを付ける（既にあれば何もしない）。カードのダブルタップ用。
    @MainActor @discardableResult
    static func addLike(feedItemId: UUID, userId: UUID, existing: PostReaction?, context: ModelContext, sync: LocalSyncEngine) -> Bool {
        guard existing == nil else { return false }
        let r = PostReaction(userId: userId, feedItemId: feedItemId, kind: .like)
        context.insert(r)
        try? context.save()
        sync.enqueue(PendingChange(entity: "post_reactions", recordId: r.id, operation: .upsert, updatedAt: r.updatedAt))
        return true
    }
}
