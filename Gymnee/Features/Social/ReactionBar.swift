import SwiftUI
import SwiftData

/// 投稿カード下のアクションバー（§6.11 / ③）。
/// 普段は「付いた絵文字＋合計数」を控えめに集約表示（未反応なら "応援" プロンプト）し、
/// タップで筋トレ絵文字トレイをスプリングで開いて 1 つ選ぶ（1 投稿 1 種別・選択中は lime リング）。
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

    @State private var pickerOpen = false

    /// この投稿への自分のリアクション（種別は問わない。1 投稿 1 つ）。
    private var mine: PostReaction? { reactions.first { $0.userId == userId } }
    private var total: Int { reactions.count }
    private func count(_ k: ReactionKind) -> Int { reactions.filter { $0.kindRaw == k.rawValue }.count }
    /// 付いている種別（多い順）。集約表示で重ねて見せる。
    private var presentKinds: [ReactionKind] {
        ReactionKind.allCases.filter { count($0) > 0 }.sorted { count($0) > count($1) }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if pickerOpen {
                tray
            } else {
                summaryButton
            }
            Spacer(minLength: Theme.Spacing.sm)
            if let onComment { commentButton(onComment) }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 2)
        .animation(.bouncy, value: pickerOpen)
        .sensoryFeedback(.impact(weight: .light), trigger: mine?.kindRaw)
    }

    // MARK: - 集約表示（折りたたみ）

    private var summaryButton: some View {
        Button { withAnimation(.bouncy) { pickerOpen = true } } label: {
            if total > 0 {
                HStack(spacing: 6) {
                    HStack(spacing: -7) {
                        ForEach(presentKinds.prefix(3), id: \.self) { k in
                            Text(k.emoji)
                                .font(.footnote)
                                .padding(5)
                                .background(Theme.bg1, in: Circle())
                                .overlay {
                                    Circle().strokeBorder(mine?.kindRaw == k.rawValue ? Theme.lime : Theme.bg3, lineWidth: 1.5)
                                }
                        }
                    }
                    Text("\(total)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(mine != nil ? Theme.lime : Theme.textSecondary)
                        .contentTransition(.numericText())
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "hands.clap.fill")
                    Text("応援").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6).padding(.trailing, 4)
        .contentShape(Rectangle())
        .accessibilityLabel(mine != nil ? "応援を変更" : "応援する")
    }

    // MARK: - 絵文字トレイ（展開）

    private var tray: some View {
        HStack(spacing: 2) {
            ForEach(Array(ReactionKind.allCases.enumerated()), id: \.element) { idx, k in
                TrayEmoji(emoji: k.emoji, selected: mine?.kindRaw == k.rawValue, index: idx) {
                    set(k)
                    withAnimation(.snappy) { pickerOpen = false }
                }
            }
            Button { withAnimation(.snappy) { pickerOpen = false } } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(7)
                    .background(Theme.bg1, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
        .padding(4)
        .background(Theme.bg2, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.bg3, lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
    }

    private func commentButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    private func set(_ k: ReactionKind) {
        ReactionActions.setReaction(feedItemId: feedItemId, userId: userId, kind: k, existing: mine, context: context, sync: sync)
    }
}

/// 絵文字トレイの 1 つ。出現時に index ごとにずらしてポップ、選択中は lime リング。
private struct TrayEmoji: View {
    let emoji: String
    let selected: Bool
    let index: Int
    let action: () -> Void

    @State private var shown = false

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.title3)
                .padding(7)
                .background(selected ? Theme.limeSoft : Color.clear, in: Circle())
                .overlay { Circle().strokeBorder(selected ? Theme.lime.opacity(0.6) : .clear, lineWidth: 1.5) }
                .scaleEffect(shown ? 1 : 0.3)
        }
        .buttonStyle(.plain)
        .onAppear { withAnimation(.bouncy.delay(Double(index) * 0.04)) { shown = true } }
        .sensoryFeedback(.selection, trigger: shown)
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
