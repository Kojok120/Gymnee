import SwiftUI
import SwiftData

/// 投稿カード下のいいね/応援バー（§6.11）。feed_item 単位でリアクションを集計・トグルする。
/// パフォーマンス: 行ごとに @Query を張らず、親が PostReaction を一括取得して該当分を渡す。
struct ReactionBar: View {
    let feedItemId: UUID
    let userId: UUID
    /// この feed_item に紐づくリアクション（親が一括取得して渡す）。
    let reactions: [PostReaction]

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            reactionButton(.like)
            reactionButton(.cheer)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.top, 2)
    }

    private func count(_ kind: ReactionKind) -> Int { reactions.filter { $0.kindRaw == kind.rawValue }.count }
    private func mine(_ kind: ReactionKind) -> PostReaction? {
        reactions.first { $0.userId == userId && $0.kindRaw == kind.rawValue }
    }

    private func reactionButton(_ kind: ReactionKind) -> some View {
        let reacted = mine(kind) != nil
        let n = count(kind)
        let symbol = reacted ? kind.icon : kind.icon.replacingOccurrences(of: ".fill", with: "")
        return Button { toggle(kind) } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                if n > 0 { Text("\(n)").font(.caption.monospacedDigit()) }
            }
            .font(.subheadline)
            .foregroundStyle(reacted ? Theme.energy : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ kind: ReactionKind) {
        if let existing = mine(kind) {
            let id = existing.id
            context.delete(existing)
            try? context.save()
            sync.enqueue(PendingChange(entity: "post_reactions", recordId: id, operation: .delete, updatedAt: .now))
        } else {
            let r = PostReaction(userId: userId, feedItemId: feedItemId, kind: kind)
            context.insert(r)
            try? context.save()
            sync.enqueue(PendingChange(entity: "post_reactions", recordId: r.id, operation: .upsert, updatedAt: r.updatedAt))
        }
    }
}
