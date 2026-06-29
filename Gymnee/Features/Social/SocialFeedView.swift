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
    @Query private var allReactions: [PostReaction]
    @Query private var allComments: [Comment]
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.friends.rawValue
    /// ソーシャル初回利用時のコミュニティガイドライン同意（1.2.5）。
    @AppStorage("gymnee.social.agreedGuidelines") private var agreedGuidelines = false

    @State private var tab = 0
    /// フレンドタブ内のサブタブ（0=フレンド, 1=合トレ履歴）。
    @State private var friendsSubtab = 0
    @State private var showAddFriend = false
    @State private var reportTarget: ReportUserTarget?
    @State private var showMyPosts = false
    /// タップで開く投稿詳細（全投稿共通：リッチ詳細＋リアクションした人＋コメント）。
    @State private var postDetail: FeedEntry?
    /// ダブルタップいいね時のハート演出対象（feed_item id）。
    @State private var burstId: UUID?
    @State private var visStore = PostVisibilityStore()
    @State private var feedEntries: [FeedEntry] = []
    /// リアクション/コメント件数の索引（毎描画の Dictionary(grouping:) を避けるためキャッシュ）。
    @State private var reactionsByItem: [UUID: [PostReaction]] = [:]
    @State private var commentCountByItem: [UUID: Int] = [:]

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
        // フォロー相手・フィード著者のプロフィール（名前/アバター）を id 指定で確実に取り込む。
        // 差分 pull が後追いフォロー相手の古い行を取り込まず「ユーザー」表示になるのを防ぐ。
        let profileIds = Set(following.map(\.followeeId))
            .union(feedItems.map(\.userId))
            .subtracting([userId])
        await sync.ensureProfiles(ids: profileIds)
        rebuildFeedEntries() // 公開範囲変更/同期取り込み後に表示を確実に更新
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
    /// feed_items の著者名（profiles 行が無い相手でも名前を出せる安全網）。
    private func feedAuthorName(for id: UUID) -> String? {
        feedItems.lazy.filter { $0.userId == id }.compactMap { $0.authorDisplayName }.first { !$0.isEmpty }
    }
    private func displayName(for id: UUID) -> String {
        if let n = profiles.first(where: { $0.id == id })?.displayName, !n.isEmpty { return n }
        if let n = feedAuthorName(for: id) { return n }
        return "ユーザー"
    }
    /// フォロー相手の表示名。プロフィール→feed著者名→follow キャッシュ→既定の順。
    /// （profiles 行が無い相手でも feed_items.author_display_name から実名を出せる）
    private func followeeName(_ f: Follow) -> String {
        if let n = profiles.first(where: { $0.id == f.followeeId })?.displayName, !n.isEmpty { return n }
        if let n = feedAuthorName(for: f.followeeId) { return n }
        if let cached = f.followeeDisplayName, !cached.isEmpty { return cached }
        return "ユーザー"
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
        // 3画面を常時マウントし不透明度だけ切替（switchの差し替えトランジション＝中身が畳まれ展開する動きを排除）。
        // レイアウトは固定されるため「枠だけ」切り替わる。
        ZStack {
            feed
                .opacity(tab == 0 ? 1 : 0)
                .allowsHitTesting(tab == 0)
            friendsList
                .opacity(tab == 1 ? 1 : 0)
                .allowsHitTesting(tab == 1)
            RankingView(userId: userId)
                .opacity(tab == 2 ? 1 : 0)
                .allowsHitTesting(tab == 2)
        }
        .navigationTitle("ソーシャル")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshFeed() }
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
                    Text("ランキング").tag(2)
                }.pickerStyle(.segmented)
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

    /// フィード描画コストの大きい構築(FeedBuilder＋ソート)を毎描画で行わずキャッシュする。
    /// データ件数が変わった時だけ再構築（タブ切替時の再計算ラグを排除）。
    private func rebuildFeedEntries() {
        let ownEntries = FeedBuilder.build(visits: visits, personalRecords: prs, workouts: workouts, defaultVisibility: defaultVisibility, visibilityStore: visStore)
        let profilesById = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let otherEntries = FeedBuilder.othersEntries(feedItems: feedItems, excludingUser: userId, profilesById: profilesById)
        // id 重複（自分の投稿と他者feed_itemのrefId衝突・多重ID孤児）で ForEach がアサーション落ちするのを防ぐ。
        var seen = Set<UUID>()
        feedEntries = (ownEntries + otherEntries)
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.id).inserted }
    }

    /// リアクション/コメント件数の索引を作り直す。reactions/comments/blocks の件数変化時のみ呼ぶ。
    private func rebuildReactionIndex() {
        reactionsByItem = Dictionary(grouping: allReactions, by: \.feedItemId)
        commentCountByItem = allComments.reduce(into: [:]) { acc, c in
            if !blockedIds.contains(c.userId) { acc[c.feedItemId, default: 0] += 1 }
        }
    }

    // フレンド/ランキングと容器(List)を統一してタブ切替の描画を滑らかに。重い構築はメモ化(feedEntries)。
    private var feed: some View {
        List {
            ForEach(feedEntries) { entry in
                feedRow(entry, reactions: reactionsByItem[entry.id] ?? [], commentCount: commentCountByItem[entry.id] ?? 0)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contextMenu { postMenu(entry) }
            }
        }
        .listStyle(.plain)
        .refreshable { await refreshFeed() }
        .background(Theme.groupedBackground)
        .overlay {
            if feedEntries.isEmpty {
                EmptyStateView(systemImage: "square.stack.3d.up", title: "フィードは空です",
                               message: "フレンドを見つけると、活動が時系列で並びます。",
                               actionTitle: "フレンドを探す", action: { showAddFriend = true })
            }
        }
        .task(id: "\(visits.count)-\(workouts.count)-\(prs.count)-\(feedItems.count)-\(profiles.count)") { rebuildFeedEntries() }
        .task(id: "\(allReactions.count)-\(allComments.count)-\(blocks.count)") { rebuildReactionIndex() }
        // カードのタップは全投稿で統一の詳細（リッチ詳細＋リアクションした人＋コメント）を開く。
        // 閉じたら編集/コメント/リアクションを反映するためフィードを作り直す。
        .onChange(of: postDetail?.id) { _, v in if v == nil { Task { await refreshFeed() } } }
        .sheet(item: $postDetail) { entry in
            PostDetailView(entry: entry, currentUserId: userId,
                           currentUserName: auth.session?.displayName,
                           onClose: { postDetail = nil })
        }
    }

    /// カード（シングルタップで開く／ダブルタップでいいね）＋いいねバー。
    /// ワークアウトもチェックインも同じカード仕様（矢印なし）に統一。
    private func feedRow(_ entry: FeedEntry, reactions: [PostReaction], commentCount: Int) -> some View {
        // 自分のリアクション（種別問わず1つ）。ダブルタップの二重付与防止にも使う。
        let myReaction = reactions.first { $0.userId == userId }
        return VStack(alignment: .leading, spacing: 4) {
            FeedCardView(entry: entry)
                .contentShape(Rectangle())
                // ダブルタップでいいね。シングルタップ（詳細/編集）と両立させるため count:2 を先に宣言。
                .onTapGesture(count: 2) { doubleTapLike(entry, existing: myReaction) }
                .onTapGesture { openEntry(entry) }
                .overlay { burstHeart(for: entry.id) }
            ReactionBar(feedItemId: entry.id, userId: userId, reactions: reactions,
                        commentCount: commentCount,
                        onComment: { postDetail = entry })
        }
    }

    /// ダブルタップいいね時に一瞬だけ表示する大きなハート。
    @ViewBuilder
    private func burstHeart(for id: UUID) -> some View {
        if burstId == id {
            Image(systemName: "heart.fill")
                .font(.system(size: 72))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 12)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    /// シングルタップ：全投稿で統一の詳細を開く（種別別リッチ詳細＋リアクションした人＋コメント）。
    private func openEntry(_ entry: FeedEntry) {
        postDetail = entry
    }

    /// ダブルタップ：いいねを付ける（既にいいね済みでもハート演出だけ出す）。
    private func doubleTapLike(_ entry: FeedEntry, existing: PostReaction?) {
        ReactionActions.addLike(feedItemId: entry.id, userId: userId, existing: existing, context: context, sync: sync)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { burstId = entry.id }
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeOut(duration: 0.25)) { if burstId == entry.id { burstId = nil } }
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

    /// フレンドタブ：上部の横並びサブタブで「フレンド」と「合トレ履歴」を切替える。
    /// 2画面を常時マウントし不透明度だけ切替（メインタブと同じ滑らかな切替）。
    private var friendsList: some View {
        VStack(spacing: 0) {
            Picker("", selection: $friendsSubtab) {
                Text("フレンド").tag(0)
                Text("合トレ履歴").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)

            ZStack {
                friendsPage
                    .opacity(friendsSubtab == 0 ? 1 : 0)
                    .allowsHitTesting(friendsSubtab == 0)
                partnersPage
                    .opacity(friendsSubtab == 1 ? 1 : 0)
                    .allowsHitTesting(friendsSubtab == 1)
            }
        }
        .background(Theme.groupedBackground)
    }

    /// フレンドサブタブ：フォロー中＋（あれば）あなたをフォロー。
    private var friendsPage: some View {
        // 行ごとの profiles.first(O(N^2)) を避けるため id 索引を一度だけ構築。
        let avatarById = Dictionary(profiles.map { ($0.id, $0.avatarURL) }, uniquingKeysWith: { a, _ in a })
        return List {
            Section("フォロー中 (\(following.count))") {
                if following.isEmpty {
                    Text("まだ誰もフォローしていません。").foregroundStyle(.secondary)
                } else {
                    ForEach(following) { f in
                        NavigationLink(value: UserRef(id: f.followeeId, name: followeeName(f))) {
                            HStack {
                                AvatarView(urlString: avatarById[f.followeeId] ?? nil, size: 32)
                                Text(followeeName(f))
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
                                reportTarget = ReportUserTarget(id: f.followeeId, displayName: followeeName(f))
                            }
                            Button("ブロック", systemImage: "hand.raised", role: .destructive) {
                                blockUser(f.followeeId, name: followeeName(f))
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

        }
        .listStyle(.plain)  // フィード/ランキングと容器スタイルを統一（切替時のインセット差による揺れを解消）
        .background(Theme.groupedBackground)
    }

    /// 合トレ履歴サブタブ：パートナー同伴の来店一覧。
    private var partnersPage: some View {
        let partnerVisits = visits.filter { !$0.partners.isEmpty }
        return List {
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
        .listStyle(.plain)
        .background(Theme.groupedBackground)
    }
}
