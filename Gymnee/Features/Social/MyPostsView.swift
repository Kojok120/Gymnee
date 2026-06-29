import SwiftUI
import SwiftData

/// 自分の投稿一覧（§6.11）。チェックイン・ワークアウト・自己ベストを時系列で表示し、
/// スワイプで削除できる。削除はフィード表示の元データ（visit / workout / personal_record）を消す。
struct MyPostsView: View {
    let userId: UUID
    /// シートを閉じる。NavigationStack 内の \.dismiss はシートを閉じないため明示的に渡す。
    var onClose: () -> Void
    let visibilityStore: PostVisibilityStore

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(AuthService.self) private var auth
    @Query private var visits: [Visit]
    @Query private var prs: [PersonalRecord]
    @Query private var workouts: [Workout]
    @Query private var allReactions: [PostReaction]
    @Query private var allComments: [Comment]
    @Query private var blocks: [Block]
    @Query private var feedItems: [FeedItem]
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.friends.rawValue
    /// 通知を最後に見た時刻。ベルの未読バッジ算出に使う。
    @AppStorage(SocialActivityBuilder.lastSeenDefaultsKey) private var lastSeenActivityAt = 0.0
    /// タップで開く投稿詳細（全投稿共通：リッチ詳細＋リアクションした人＋コメント）。
    @State private var postDetail: FeedEntry?
    /// 通知一覧（ベルから push）。
    @State private var showInbox = false

    init(userId: UUID, visibilityStore: PostVisibilityStore, onClose: @escaping () -> Void) {
        self.userId = userId
        self.visibilityStore = visibilityStore
        self.onClose = onClose
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId }, sort: \Visit.visitedAt, order: .reverse)
        _prs = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId }, sort: \PersonalRecord.achievedAt, order: .reverse)
        _workouts = Query(filter: #Predicate<Workout> { $0.userId == userId }, sort: \Workout.date, order: .reverse)
        _blocks = Query(filter: #Predicate<Block> { $0.blockerId == userId })
    }

    private var defaultVisibility: Visibility { Visibility(rawValue: defaultVisibilityRaw) ?? .public }
    private var blockedIds: Set<UUID> { Set(blocks.map(\.blockedId)) }
    /// 反応/コメントが参照する自分の投稿（feed_item）の id 集合。
    private var myPostIds: Set<UUID> { Set(feedItems.filter { $0.userId == userId }.map(\.id)) }
    /// 自分の投稿に付いた他者反応の未読数（ベルの赤バッジ）。
    private var socialUnread: Int {
        SocialActivityFeed.unreadCount(reactions: allReactions, comments: allComments,
                                       myPostIds: myPostIds, currentUserId: userId,
                                       blockedIds: blockedIds, lastSeen: lastSeenActivityAt)
    }

    private var entries: [FeedEntry] {
        FeedBuilder.build(
            visits: visits,
            personalRecords: prs,
            workouts: workouts,
            defaultVisibility: defaultVisibility,
            visibilityStore: visibilityStore
        )
    }

    var body: some View {
        // 毎描画の O(N^2) first(where:) を避けるため id 索引と reaction を一度だけ構築。
        let reactionsByItem = Dictionary(grouping: allReactions, by: \.feedItemId)
        return List {
            ForEach(entries) { entry in
                row(entry, reactions: reactionsByItem[entry.id] ?? [])
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button("削除", role: .destructive) { delete(entry) }
                    }
                    .contextMenu { postMenu(entry) }
            }
        }
        .listStyle(.plain)
        .background(Theme.groupedBackground)
        .overlay {
            if entries.isEmpty {
                EmptyStateView(systemImage: "square.stack.3d.up", title: "投稿がありません", message: "チェックイン・ワークアウト・自己ベストがここに並びます。")
            }
        }
        .navigationTitle("自分の投稿")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("閉じる") { onClose() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInbox = true } label: {
                    Image(systemName: "bell").notificationBadge(socialUnread)
                }
                .accessibilityLabel("通知")
            }
        }
        .navigationDestination(isPresented: $showInbox) {
            SocialActivityView(userId: userId)
        }
        .sheet(item: $postDetail) { entry in
            PostDetailView(entry: entry, currentUserId: userId,
                           currentUserName: auth.session?.displayName,
                           onClose: { postDetail = nil })
        }
    }

    /// カード（タップで詳細）＋いいね/応援バー。
    private func row(_ entry: FeedEntry, reactions: [PostReaction]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            card(entry)
            ReactionBar(feedItemId: entry.id, userId: userId, reactions: reactions)
        }
    }

    /// タップで全投稿共通の詳細（リッチ詳細＋リアクションした人＋コメント）を開く。
    private func card(_ entry: FeedEntry) -> some View {
        Button { postDetail = entry } label: { FeedCardView(entry: entry) }
            .buttonStyle(.plain)
    }

    /// 投稿の長押しメニュー：公開範囲の変更（編集はカードのタップで開く）。
    @ViewBuilder
    private func postMenu(_ entry: FeedEntry) -> some View {
        Menu("公開範囲") {
            ForEach(Visibility.allCases, id: \.self) { v in
                Button { visibilityStore.set(v, for: entry.id) } label: {
                    Label(v.label, systemImage: (visibilityStore.visibility(for: entry.id) ?? defaultVisibility) == v ? "checkmark" : "")
                }
            }
        }
    }

    private func delete(_ entry: FeedEntry) {
        switch entry.kind {
        case .visit:
            guard let v = visits.first(where: { $0.id == entry.id }) else { return }
            PhotoStore.delete(v.localPhotoFilename)
            context.delete(v)
            try? context.save()
            sync.enqueue(PendingChange(entity: "visits", recordId: entry.id, operation: .delete, updatedAt: .now))
        case .pr:
            guard let pr = prs.first(where: { $0.id == entry.id }) else { return }
            context.delete(pr)
            try? context.save()
            sync.enqueue(PendingChange(entity: "personal_records", recordId: entry.id, operation: .delete, updatedAt: .now))
        case .workout:
            guard let w = workouts.first(where: { $0.id == entry.id }) else { return }
            context.delete(w)
            try? context.save()
            sync.enqueue(PendingChange(entity: "workouts", recordId: entry.id, operation: .delete, updatedAt: .now))
        }
    }
}
