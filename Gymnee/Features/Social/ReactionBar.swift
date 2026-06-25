import SwiftUI
import SwiftData

/// 投稿カード下のアクションバー（§6.11 / ③）。筋トレ絵文字の応援リアクション＋コメント導線。
/// 応援は 1 ユーザー 1 投稿につき 1 種別（タップで切替/取消）。
/// パフォーマンス: 行ごとに @Query を張らず、親が PostReaction/Comment を一括取得して件数を渡す。
struct ReactionBar: View {
    let feedItemId: UUID
    let userId: UUID
    /// この feed_item に紐づくリアクション（親が一括取得して渡す）。
    let reactions: [PostReaction]
    /// コメント件数（親が一括取得して渡す）。0 ならバッジ非表示。
    var commentCount: Int = 0
    /// コメントを開く（nil ならコメントボタン非表示）。
    var onComment: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync

    /// この投稿への自分のリアクション（種別は問わない。1 投稿 1 つ）。
    private var mine: PostReaction? { reactions.first { $0.userId == userId } }
    private func count(_ k: ReactionKind) -> Int { reactions.filter { $0.kindRaw == k.rawValue }.count }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ReactionKind.allCases, id: \.self) { k in
                reactionChip(k)
            }
            Spacer(minLength: Theme.Spacing.sm)
            if let onComment {
                Button(action: onComment) {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                        if commentCount > 0 { Text("\(commentCount)").font(.caption.monospacedDigit()) }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8).padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("コメント")
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .sensoryFeedback(.impact(weight: .light), trigger: mine?.kindRaw)
    }

    private func reactionChip(_ k: ReactionKind) -> some View {
        let selected = mine?.kindRaw == k.rawValue
        let c = count(k)
        return Button { set(k) } label: {
            HStack(spacing: 4) {
                Text(k.emoji).font(.subheadline)
                if c > 0 {
                    Text("\(c)").font(.caption.monospacedDigit())
                        .foregroundStyle(selected ? Theme.lime : .secondary)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 9)
            .background(selected ? Theme.limeSoft : Theme.bg2, in: Capsule())
            .overlay { Capsule().strokeBorder(selected ? Theme.lime.opacity(0.5) : .clear, lineWidth: 1) }
            .contentShape(Capsule())
            .scaleEffect(selected ? 1.06 : 1)
            .animation(.snappy, value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(k.label)
    }

    private func set(_ k: ReactionKind) {
        ReactionActions.setReaction(feedItemId: feedItemId, userId: userId, kind: k, existing: mine, context: context, sync: sync)
    }
}

/// リアクション操作の共有ロジック（ReactionBar とフィードのダブルタップから利用）。
enum ReactionActions {
    /// 応援をセット（無ければ追加 / 別種別なら付け替え / 同種別なら取消）。1 投稿 1 種別。
    /// サーバ unique(user_id, feed_item_id, kind) と衝突しないよう、付け替えは旧削除＋新規追加で行う。
    @MainActor static func setReaction(feedItemId: UUID, userId: UUID, kind: ReactionKind, existing: PostReaction?, context: ModelContext, sync: LocalSyncEngine) {
        if let existing {
            let oldId = existing.id
            if existing.kindRaw == kind.rawValue {
                context.delete(existing)
                try? context.save()
                sync.enqueue(PendingChange(entity: "post_reactions", recordId: oldId, operation: .delete, updatedAt: .now))
            } else {
                context.delete(existing)
                let r = PostReaction(userId: userId, feedItemId: feedItemId, kind: kind)
                context.insert(r)
                try? context.save()
                sync.enqueue(PendingChange(entity: "post_reactions", recordId: oldId, operation: .delete, updatedAt: .now))
                sync.enqueue(PendingChange(entity: "post_reactions", recordId: r.id, operation: .upsert, updatedAt: r.updatedAt))
            }
        } else {
            let r = PostReaction(userId: userId, feedItemId: feedItemId, kind: kind)
            context.insert(r)
            try? context.save()
            sync.enqueue(PendingChange(entity: "post_reactions", recordId: r.id, operation: .upsert, updatedAt: r.updatedAt))
        }
    }

    /// 既存リアクションが無ければ ❤️ を付ける（カードのダブルタップ用）。既にあれば何もしない。
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
