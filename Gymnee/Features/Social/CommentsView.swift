import SwiftUI
import SwiftData

/// 投稿（feed_item）への公開コメント一覧＋投稿（③）。
/// DM ではなく「不特定/多数が読むオープンな場」。ブロック相手のコメントは非表示、各コメントは通報可能（UGC安全 1.2.5）。
struct CommentsView: View {
    let feedItemId: UUID
    let currentUserId: UUID
    var currentUserName: String?
    var onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync

    @Query private var comments: [Comment]
    @Query private var blocks: [Block]
    @Query private var profiles: [Profile]

    @State private var draft = ""
    @State private var reportTarget: CommentReportTarget?
    @FocusState private var composerFocused: Bool

    init(feedItemId: UUID, currentUserId: UUID, currentUserName: String? = nil, onClose: @escaping () -> Void) {
        self.feedItemId = feedItemId
        self.currentUserId = currentUserId
        self.currentUserName = currentUserName
        self.onClose = onClose
        _comments = Query(filter: #Predicate<Comment> { $0.feedItemId == feedItemId }, sort: \Comment.createdAt, order: .forward)
        _blocks = Query(filter: #Predicate<Block> { $0.blockerId == currentUserId })
    }

    private var blockedIds: Set<UUID> { Set(blocks.map(\.blockedId)) }
    private var visibleComments: [Comment] { comments.filter { !blockedIds.contains($0.userId) } }

    private func name(_ c: Comment) -> String {
        if let n = profiles.first(where: { $0.id == c.userId })?.displayName, !n.isEmpty { return n }
        if let n = c.authorDisplayName, !n.isEmpty { return n }
        return "ユーザー"
    }
    private func avatar(_ c: Comment) -> String? { profiles.first(where: { $0.id == c.userId })?.avatarURL }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { (1...500).contains(trimmedDraft.count) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if visibleComments.isEmpty {
                    EmptyStateView(systemImage: "bubble.left.and.bubble.right",
                                   title: "コメントはまだありません",
                                   message: "最初の応援コメントを送りましょう。")
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(visibleComments) { c in
                            commentRow(c)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .background(Theme.groupedBackground)
                }
                composer
            }
            .background(Theme.bg0)
            .navigationTitle("コメント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { onClose() } }
            }
            .sheet(item: $reportTarget) { t in
                ReportSheet(reporterId: currentUserId, reportedUserId: t.userId,
                            reportedDisplayName: t.name, contextType: "comment", contextId: t.id)
            }
        }
    }

    private func commentRow(_ c: Comment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(urlString: avatar(c), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name(c)).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                    Text(c.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(c.text).font(.subheadline).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if c.userId == currentUserId {
                Button("削除", systemImage: "trash", role: .destructive) { delete(c) }
            } else {
                Button("通報", systemImage: "flag") {
                    reportTarget = CommentReportTarget(id: c.id, userId: c.userId, name: name(c))
                }
                Button("ブロック", systemImage: "hand.raised", role: .destructive) {
                    Moderation.block(blockerId: currentUserId, blockedId: c.userId, displayName: name(c), context: context, sync: sync)
                }
            }
        }
        .swipeActions {
            if c.userId == currentUserId {
                Button("削除", role: .destructive) { delete(c) }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
            TextField("コメントを追加…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($composerFocused)
                .padding(.vertical, 8).padding(.horizontal, Theme.Spacing.md)
                .background(Theme.bg2, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Theme.lime : Theme.textTertiary)
            }
            .disabled(!canSend)
            .sensoryFeedback(.success, trigger: visibleComments.count)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.bg1)
    }

    private func send() {
        let t = trimmedDraft
        guard (1...500).contains(t.count) else { return }
        let c = Comment(feedItemId: feedItemId, userId: currentUserId, authorDisplayName: currentUserName, text: t)
        context.insert(c)
        try? context.save()
        sync.enqueue(PendingChange(entity: "comments", recordId: c.id, operation: .upsert, updatedAt: c.updatedAt))
        draft = ""
        composerFocused = false
        Task { await sync.syncNow() }
    }

    private func delete(_ c: Comment) {
        let id = c.id
        context.delete(c)
        try? context.save()
        sync.enqueue(PendingChange(entity: "comments", recordId: id, operation: .delete, updatedAt: .now))
    }
}

/// コメント通報シート提示用ターゲット（`sheet(item:)` 用）。
struct CommentReportTarget: Identifiable {
    let id: UUID      // commentId（reports.context_id）
    let userId: UUID  // reportedUserId
    let name: String
}
