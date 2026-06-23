import SwiftUI
import SwiftData

/// フォロー中などの他ユーザーのプロフィール（§6.11）。
/// 公開スタッツ（取り込めている投稿数）＋公開投稿（feed_items）＋フォロー操作を表示する。
struct UserProfileView: View {
    let targetUserId: UUID
    let currentUserId: UUID
    let fallbackName: String

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Query private var theirFeedItems: [FeedItem]
    @Query private var profiles: [Profile]
    @Query private var myFollows: [Follow]
    @Query private var allReactions: [PostReaction]

    init(targetUserId: UUID, currentUserId: UUID, fallbackName: String) {
        self.targetUserId = targetUserId
        self.currentUserId = currentUserId
        self.fallbackName = fallbackName
        _theirFeedItems = Query(
            filter: #Predicate<FeedItem> { $0.userId == targetUserId },
            sort: \FeedItem.createdAt, order: .reverse
        )
        _myFollows = Query(filter: #Predicate<Follow> {
            $0.followerId == currentUserId && $0.followeeId == targetUserId
        })
    }

    private var profile: Profile? { profiles.first { $0.id == targetUserId } }
    private var displayName: String { profile?.displayName ?? fallbackName }
    private var isFollowing: Bool { !myFollows.isEmpty }

    private var entries: [FeedEntry] {
        var byId: [UUID: Profile] = [:]
        if let profile { byId[targetUserId] = profile }
        return FeedBuilder.othersEntries(feedItems: theirFeedItems, excludingUser: currentUserId, profilesById: byId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                header
                if entries.isEmpty {
                    EmptyStateView(systemImage: "square.stack.3d.up", title: "公開された投稿はありません",
                                   message: "この人の公開/友達限定の投稿がここに並びます。")
                        .padding(.top, Theme.Spacing.xl)
                } else {
                    let reactionsByItem = Dictionary(grouping: allReactions, by: \.feedItemId)
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            FeedCardView(entry: entry)
                            ReactionBar(feedItemId: entry.id, userId: currentUserId, reactions: reactionsByItem[entry.id] ?? [])
                        }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.groupedBackground)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.md) {
            AvatarView(urlString: profile?.avatarURL, size: 88)
            Text(displayName).font(.title2.bold())
            Text("投稿 \(theirFeedItems.count) 件").font(.caption).foregroundStyle(.secondary)
            Button {
                isFollowing ? unfollow() : follow()
            } label: {
                Label(isFollowing ? "フォロー中" : "フォローする",
                      systemImage: isFollowing ? "checkmark" : "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isFollowing ? Color.secondary : Theme.energy)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .gymneeCard()
    }

    private func follow() {
        guard myFollows.isEmpty else { return }
        let f = Follow(followerId: currentUserId, followeeId: targetUserId, followeeDisplayName: displayName)
        context.insert(f)
        try? context.save()
        sync.enqueue(PendingChange(entity: "follows", recordId: f.id, operation: .upsert, updatedAt: f.updatedAt))
    }

    private func unfollow() {
        for f in myFollows {
            let id = f.id
            context.delete(f)
            sync.enqueue(PendingChange(entity: "follows", recordId: id, operation: .delete, updatedAt: .now))
        }
        try? context.save()
    }
}
