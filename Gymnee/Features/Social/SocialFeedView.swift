import SwiftUI
import SwiftData

/// ソーシャル（§6.11）。フィード（来店/PR/ワークアウト）と合トレ・フォロー。
/// 実マルチユーザ連携は Supabase 接続後。今回はローカルデータ＋UI＋抽象。
struct SocialFeedView: View {
    @Environment(AuthService.self) private var auth
    /// 起動時に表示するタブ（0=フィード, 1=フレンド）。ディープリンク/検証ハーネス用。
    var initialTab: Int = 0

    var body: some View {
        NavigationStack {
            if let uid = auth.currentUserId {
                SocialContent(userId: uid, initialTab: initialTab)
            } else {
                EmptyStateView(systemImage: "person.2", title: "未ログイン")
            }
        }
    }
}

/// 他ユーザーのプロフィールへ遷移するための値（フレンド一覧から）。
struct UserRef: Hashable {
    let id: UUID
    let name: String
}

private struct SocialContent: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(AuthService.self) private var auth

    @Query private var visits: [Visit]
    @Query private var prs: [PersonalRecord]
    @Query private var workouts: [Workout]
    @Query private var follows: [Follow]
    @Query private var blocks: [Block]
    @Query private var profiles: [Profile]
    /// 自分＋フォロー中の他人の feed_items（サーバーから RLS 経由で取り込む）。
    @Query private var feedItems: [FeedItem]
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.public.rawValue
    /// ソーシャル初回利用時のコミュニティガイドライン同意（1.2.5）。
    @AppStorage("gymnee.social.agreedGuidelines") private var agreedGuidelines = false

    @State private var tab = 0
    @State private var showAddFriend = false
    @State private var reportTarget: ReportUserTarget?
    @State private var showMyPosts = false
    @State private var editVisit: Visit?
    @State private var visStore = PostVisibilityStore()

    init(userId: UUID, initialTab: Int = 0) {
        self.userId = userId
        _tab = State(initialValue: initialTab)
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId }, sort: \Visit.visitedAt, order: .reverse)
        _prs = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId }, sort: \PersonalRecord.achievedAt, order: .reverse)
        _workouts = Query(filter: #Predicate<Workout> { $0.userId == userId }, sort: \Workout.date, order: .reverse)
        // 自分が follower か followee の両方を取得（相互判定のため）。
        _follows = Query(filter: #Predicate<Follow> { $0.followerId == userId || $0.followeeId == userId }, sort: \Follow.createdAt)
        _blocks = Query(filter: #Predicate<Block> { $0.blockerId == userId })
    }

    private var defaultVisibility: Visibility { Visibility(rawValue: defaultVisibilityRaw) ?? .public }

    /// 自分の投稿を feed_items として発行し、最新差分を同期（push＋pull）する。
    private func refreshFeed() async {
        FeedPublisher.publishOwnPosts(
            userId: userId,
            authorName: auth.session?.displayName,
            context: context,
            visibilityStore: visStore,
            defaultVisibility: defaultVisibility,
            sync: sync
        )
        await sync.syncNow()
    }

    // MARK: - フォロー関係の導出
    /// 自分がブロック中のユーザー集合（一覧・相互判定から除外）。
    private var blockedIds: Set<UUID> { Set(blocks.map(\.blockedId)) }
    /// 自分がフォローしている関係（ブロック相手を除外）。
    private var following: [Follow] { follows.filter { $0.followerId == userId && !blockedIds.contains($0.followeeId) } }
    /// 自分をフォローしている人の userId 集合（ブロック相手を除外）。
    private var followerIds: Set<UUID> { Set(follows.filter { $0.followeeId == userId && !blockedIds.contains($0.followerId) }.map(\.followerId)) }
    /// 相互フォローか（相手も自分をフォローしている）。
    private func isMutual(_ f: Follow) -> Bool { followerIds.contains(f.followeeId) }
    /// 自分をフォローしているが自分はまだフォローし返していない人（ブロック相手を除外）。
    private var pendingFollowBack: [Follow] {
        let followingIds = Set(following.map(\.followeeId))
        return follows.filter { $0.followeeId == userId && !followingIds.contains($0.followerId) && !blockedIds.contains($0.followerId) }
    }
    private func displayName(for id: UUID) -> String {
        profiles.first(where: { $0.id == id })?.displayName ?? "ユーザー"
    }

    /// 対象ユーザーをブロック（フォロー双方向解除＋Block作成・同期）。
    private func blockUser(_ id: UUID, name: String) {
        Moderation.block(blockerId: userId, blockedId: id, displayName: name, context: context, sync: sync)
    }

    private func unfollow(_ f: Follow) {
        let id = f.id
        context.delete(f)
        try? context.save()
        sync.enqueue(PendingChange(entity: "follows", recordId: id, operation: .delete, updatedAt: .now))
    }

    private func followBack(_ targetId: UUID) {
        guard !following.contains(where: { $0.followeeId == targetId }) else { return }
        let follow = Follow(followerId: userId, followeeId: targetId, followeeDisplayName: displayName(for: targetId))
        context.insert(follow)
        try? context.save()
        sync.enqueue(PendingChange(entity: "follows", recordId: follow.id, operation: .upsert, updatedAt: follow.updatedAt))
    }

    var body: some View {
        Group {
            if agreedGuidelines {
                mainContent
            } else {
                CommunityGuidelinesGate { agreedGuidelines = true }
                    .navigationTitle("ソーシャル")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(item: $reportTarget) { t in
            ReportSheet(reporterId: userId, reportedUserId: t.id, reportedDisplayName: t.displayName)
        }
    }

    private var mainContent: some View {
        Group {
            switch tab {
            case 1: friendsList
            default: feed
            }
        }
        .navigationTitle("ソーシャル")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshFeed() }
        .refreshable { await refreshFeed() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showMyPosts = true } label: {
                    Image(systemName: "person.crop.rectangle.stack")
                }
                .accessibilityLabel("自分の投稿")
            }
            ToolbarItem(placement: .principal) {
                Picker("", selection: $tab) {
                    Text("フィード").tag(0)
                    Text("フレンド").tag(1)
                }.pickerStyle(.segmented).frame(width: 200)
            }
        }
        .sheet(isPresented: $showMyPosts) {
            NavigationStack { MyPostsView(userId: userId, visibilityStore: visStore, onClose: { showMyPosts = false }) }
        }
        .onChange(of: showMyPosts) { _, shown in if !shown { Task { await refreshFeed() } } }
        .sheet(isPresented: $showAddFriend) { AddFriendView(userId: userId) }
        .navigationDestination(for: UserRef.self) { ref in
            UserProfileView(targetUserId: ref.id, currentUserId: userId, fallbackName: ref.name)
        }
    }

    // MARK: - Feed

    private var feed: some View {
        let ownEntries = FeedBuilder.build(visits: visits, personalRecords: prs, workouts: workouts, defaultVisibility: defaultVisibility, visibilityStore: visStore)
        let profilesById = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let otherEntries = FeedBuilder.othersEntries(feedItems: feedItems, excludingUser: userId, profilesById: profilesById)
        let entries = (ownEntries + otherEntries).sorted { $0.date > $1.date }
        return ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(entries) { entry in
                    feedRow(entry)
                        .contextMenu { postMenu(entry) }
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.groupedBackground)
        .overlay {
            if entries.isEmpty {
                EmptyStateView(systemImage: "square.stack.3d.up", title: "フィードは空です", message: "チェックインやワークアウトが時系列で並びます。")
            }
        }
        .onChange(of: editVisit) { _, v in if v == nil { Task { await refreshFeed() } } }
        .sheet(item: $editVisit) { visit in
            CheckInEditView(visit: visit, visibilityStore: visStore)
        }
    }

    /// タップで開く（ワークアウト＝詳細、チェックイン＝編集）。仕様を統一。
    @ViewBuilder
    private func feedRow(_ entry: FeedEntry) -> some View {
        if entry.kind == .workout, let workout = workouts.first(where: { $0.id == entry.id }) {
            NavigationLink {
                WorkoutDetailView(workout: workout)
            } label: {
                FeedCardView(entry: entry)
            }
            .buttonStyle(.plain)
        } else if entry.kind == .visit, let visit = visits.first(where: { $0.id == entry.id }) {
            Button { editVisit = visit } label: { FeedCardView(entry: entry) }
                .buttonStyle(.plain)
        } else {
            FeedCardView(entry: entry)
        }
    }

    /// 投稿の長押しメニュー：公開範囲の変更（自分の投稿のみ。編集はカードのタップで開く）。
    @ViewBuilder
    private func postMenu(_ entry: FeedEntry) -> some View {
        if !entry.isFromOther {
            Menu("公開範囲") {
                ForEach(Visibility.allCases, id: \.self) { v in
                    Button {
                        visStore.set(v, for: entry.id)
                        Task { await refreshFeed() }
                    } label: {
                        Label(v.label, systemImage: (visStore.visibility(for: entry.id) ?? defaultVisibility) == v ? "checkmark" : "")
                    }
                }
            }
        }
    }

    // MARK: - Friends / 合トレ

    private var friendsList: some View {
        List {
            Section("フォロー中 (\(following.count))") {
                if following.isEmpty {
                    Text("まだ誰もフォローしていません。").foregroundStyle(.secondary)
                } else {
                    ForEach(following) { f in
                        NavigationLink(value: UserRef(id: f.followeeId, name: f.followeeDisplayName ?? "ユーザー")) {
                            HStack {
                                AvatarView(urlString: profiles.first { $0.id == f.followeeId }?.avatarURL, size: 32)
                                Text(f.followeeDisplayName ?? "ユーザー")
                                Spacer()
                                if isMutual(f) {
                                    Label("相互", systemImage: "arrow.left.arrow.right")
                                        .font(.caption2.bold()).foregroundStyle(Theme.energy)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Theme.energy.opacity(0.15), in: Capsule())
                                }
                            }
                        }
                        .swipeActions { Button("解除", role: .destructive) { unfollow(f) } }
                        .contextMenu {
                            Button("通報", systemImage: "flag") {
                                reportTarget = ReportUserTarget(id: f.followeeId, displayName: f.followeeDisplayName ?? "ユーザー")
                            }
                            Button("ブロック", systemImage: "hand.raised", role: .destructive) {
                                blockUser(f.followeeId, name: f.followeeDisplayName ?? "ユーザー")
                            }
                        }
                    }
                }
                Button { showAddFriend = true } label: {
                    Label("ユーザーを探す", systemImage: "magnifyingglass")
                }
            }

            if !pendingFollowBack.isEmpty {
                Section("あなたをフォロー") {
                    ForEach(pendingFollowBack) { f in
                        HStack {
                            Image(systemName: "person").foregroundStyle(.secondary)
                            Text(displayName(for: f.followerId))
                            Spacer()
                            Button("フォローし返す") { followBack(f.followerId) }
                                .buttonStyle(.borderedProminent).tint(Theme.energy).controlSize(.small)
                        }
                        .swipeActions {
                            Button("ブロック", role: .destructive) { blockUser(f.followerId, name: displayName(for: f.followerId)) }
                        }
                        .contextMenu {
                            Button("通報", systemImage: "flag") {
                                reportTarget = ReportUserTarget(id: f.followerId, displayName: displayName(for: f.followerId))
                            }
                            Button("ブロック", systemImage: "hand.raised", role: .destructive) {
                                blockUser(f.followerId, name: displayName(for: f.followerId))
                            }
                        }
                    }
                }
            }

            Section("合トレ履歴") {
                let partnerVisits = visits.filter { !$0.partners.isEmpty }
                if partnerVisits.isEmpty {
                    Text("合トレ記録はまだありません。").foregroundStyle(.secondary)
                } else {
                    ForEach(partnerVisits) { v in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.gym?.name ?? "ジム").font(.subheadline.bold())
                            Text(v.partners.compactMap(\.partnerDisplayName).joined(separator: "・"))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(v.visitedAt, format: .dateTime.year().month().day())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
