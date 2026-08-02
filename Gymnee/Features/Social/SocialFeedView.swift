import SwiftUI
import SwiftData

/// ソーシャル（§6.11）。フィード（来店/PR/ワークアウト）とフォロー・ランキング。
/// フレンドは右上アイコンから開く画面に集約。実マルチユーザ連携は Supabase 接続後。
struct SocialFeedView: View {
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync
    /// 起動時に表示するタブ（0=フィード, 1=ランキング）。ディープリンク/検証ハーネス用。
    /// 起動時にフレンド画面を開く（検証ハーネス -gymneeScreen friends 用）。
    var openFriends: Bool = false

    /// 値ベース遷移用のパス（フレンド画面・招待者プロフィールの自動 push にも使う）。
    @State private var path = NavigationPath()
    @State private var didAutoOpenFriends = false
    /// ガイドライン同意ゲート（SocialContent と同一キー）。未同意の間は List が描画されず
    /// navigationDestination が未登録のため、招待の消費（push）は同意後まで保留する。
    @AppStorage("gymnee.social.agreedGuidelines") private var agreedGuidelines = false

    var body: some View {
        NavigationStack(path: $path) {
            if sync.isRemoteEnabled && !auth.isPermanentAccount {
                // ゲスト（未サインイン・匿名セッション含む）にはフィードの代わりにサインイン促しを出す。
                // フォロー・応援・コメント・公開投稿は本人性のあるアカウント限定（RLS 0031 とも整合）。
                signInPrompt
            } else if let uid = auth.currentUserId {
                SocialContent(userId: uid)
                    .onAppear {
                        // 検証ハーネス: 一度だけフレンド画面を自動 push（戻り時の再 push を防ぐ）。
                        if openFriends && !didAutoOpenFriends {
                            didAutoOpenFriends = true
                            path.append(SocialRoute.friends)
                        }
                        consumePendingInvite(currentUserId: uid)
                    }
                    // アプリ起動中に招待リンクを開いた場合（RootView がタブを切替えた直後に届く）。
                    .onReceive(NotificationCenter.default.publisher(for: .gymneeOpenDestination)) { note in
                        if note.userInfo?["type"] as? String == "invite" {
                            consumePendingInvite(currentUserId: uid)
                        }
                    }
                    // 招待経由の新規ユーザー: ガイドライン同意の瞬間に保留招待を拾う。
                    .onChange(of: agreedGuidelines) { _, agreed in
                        if agreed { consumePendingInvite(currentUserId: uid) }
                    }
            } else {
                EmptyStateView(systemImage: "person.2", title: "未ログイン")
            }
        }
    }

    /// ゲスト向けのサインイン促し（フレンド機能の入口で初めてサインインを求める）。
    private var signInPrompt: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.lime)
                    .padding(.top, 48)
                Text("フレンド機能にはサインインが必要です")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text("友達のフォロー、応援の送り合い、招待リンクを使うにはサインインしてください。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                BackendSignInButtons()
                    .padding(.top, Theme.Spacing.sm)
            }
            .padding(Theme.Spacing.xl)
        }
        .navigationTitle("ソーシャル")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 保留中の招待（招待リンクで開いた相手）があれば一度だけ消費し、招待者プロフィールを push する。
    /// 未サインインで開いた場合もサインイン完了後にここで拾う。
    private func consumePendingInvite(currentUserId: UUID) {
        guard agreedGuidelines else { return } // 同意前は消費せず持ち越す
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: InviteLink.pendingDefaultsKey) else { return }
        defaults.removeObject(forKey: InviteLink.pendingDefaultsKey)
        guard let inviter = UUID(uuidString: raw), inviter != currentUserId else { return }
        // 先に画面を出し、プロフィール（名前/アバター）は裏で取り込んで @Query の反映に任せる。
        path.append(UserRef(id: inviter, name: "ユーザー"))
        Task { await sync.ensureProfiles(ids: [inviter]) }
    }
}

/// ソーシャル内の値ベース遷移先。フレンド画面は当初 navigationDestination(isPresented:) で
/// 提示していたが、同一スタックの値 push（UserRef）と競合して遷移がループするため、
/// 値ベース（NavigationLink(value:)＋ルート宣言）に統一する。
enum SocialRoute: Hashable {
    case friends
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

    @Query private var prs: [PersonalRecord]
    @Query private var workouts: [Workout]
    @Query private var follows: [Follow]
    @Query private var blocks: [Block]
    @Query private var profiles: [Profile]
    /// 自分＋フォロー中の他人の feed_items（サーバーから RLS 経由で取り込む）。
    @Query private var feedItems: [FeedItem]
    @Query private var allReactions: [PostReaction]
    @Query private var allComments: [Comment]
    /// ソーシャル初回利用時のコミュニティガイドライン同意（1.2.5）。
    @AppStorage("gymnee.social.agreedGuidelines") private var agreedGuidelines = false
    /// 通知（自分の投稿への他者反応）を最後に見た時刻。アイコンの未読バッジ算出に使う。
    @AppStorage(SocialActivityBuilder.lastSeenDefaultsKey) private var lastSeenActivityAt = 0.0

    @State private var reportTarget: ReportUserTarget?
    /// 削除の確認待ち（記録ごと消える不可逆操作なので、長押しから直接は実行しない）。
    @State private var deleteTarget: FeedEntry?
    @State private var showActivity = false
    /// タップで開く投稿詳細（全投稿共通：リッチ詳細＋リアクションした人＋コメント）。
    @State private var postDetail: FeedEntry?
    /// ダブルタップいいね時のハート演出対象（feed_item id）。
    @State private var burstId: UUID?
    @State private var feedEntries: [FeedEntry] = []

    init(userId: UUID) {
        self.userId = userId
        _prs = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId }, sort: \PersonalRecord.achievedAt, order: .reverse)
        _workouts = Query(filter: #Predicate<Workout> { $0.userId == userId }, sort: \Workout.date, order: .reverse)
        // 自分が follower か followee の両方を取得（相互判定のため）。
        _follows = Query(filter: #Predicate<Follow> { $0.followerId == userId || $0.followeeId == userId }, sort: \Follow.createdAt)
        _blocks = Query(filter: #Predicate<Block> { $0.blockerId == userId })
    }


    /// 公開済み投稿を最新の元データへ追従させ（新規作成はしない）、最新差分を同期（push＋pull）する。
    private func refreshFeed() async {
        FeedPublisher.syncPublishedPosts(userId: userId, authorName: auth.session?.displayName, context: context, sync: sync)
        await sync.syncNow()
        // フォロー相手・フォロワー・フィード著者のプロフィール（名前/アバター）を id 指定で確実に取り込む。
        // 差分 pull は相手プロフィールの古い行を取り込まないため、ここに含めない相手は「ユーザー」表示に
        // なってしまう（過去にフォロワーが漏れており、フォローバックするまで名前が出ないバグがあった）。
        let profileIds = Set(following.map(\.followeeId))
            .union(followerIds)
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
    /// 反応/コメントが参照する自分の投稿（feed_item）の id 集合。
    /// feed_item.id == 元データ id。削除直後でも実体（pr/workout）から導き、stale な feedItems に依存しない。
    private var myPostIds: Set<UUID> {
        Set(prs.map(\.id))
            .union(workouts.filter { $0.completedAt != nil }.map(\.id))
    }
    /// 自分の投稿に付いた他者反応の未読数（アイコンの赤バッジ）。
    private var socialUnread: Int {
        SocialActivityFeed.unreadCount(reactions: allReactions, comments: allComments,
                                       myPostIds: myPostIds, currentUserId: userId,
                                       blockedIds: blockedIds, lastSeen: lastSeenActivityAt)
    }
    /// feed_items の著者名（profiles 行が無い相手でも名前を出せる安全網）。
    private func feedAuthorName(for id: UUID) -> String? {
        feedItems.lazy.filter { $0.userId == id }.compactMap { $0.authorDisplayName }.first { !$0.isEmpty }
    }
    /// 表示名の単発解決（followBack などのアクション用。行描画は friendsScreen 内の辞書引き resolveName を使う）。
    private func displayName(for id: UUID) -> String {
        if let n = profiles.first(where: { $0.id == id })?.displayName, !n.isEmpty { return n }
        if let n = feedAuthorName(for: id) { return n }
        return "ユーザー"
    }

    /// 対象ユーザーをブロック（フォロー双方向解除＋Block作成・同期）。
    private func blockUser(_ id: UUID, name: String) {
        Moderation.block(blockerId: userId, blockedId: id, displayName: name, context: context, sync: sync)
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
            ReportSheet(reporterId: userId, reportedUserId: t.id, reportedDisplayName: t.displayName,
                        contextType: t.contextType, contextId: t.contextId)
        }
    }

    /// ランキングは撤去済み（競争より継続を主役にする）。画面はフィード 1 枚で、
    /// 左上＝通知、右上＝友達追加という Twitter / Instagram と同じ配置に揃える。
    private var mainContent: some View {
        feed
        .navigationTitle("フィード")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshFeed() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // 通知は「自分の投稿」の中に埋もれていたのをツールバー直下へ昇格させる。
                Button { showActivity = true } label: {
                    Image(systemName: "bell")
                }
                .notificationBadge(socialUnread)
                .accessibilityLabel("通知")
            }
            ToolbarItem(placement: .topBarTrailing) {
                // フレンド画面へは値ベースで push（isPresented 型 destination は UserRef の
                // 値 push と競合してループするため使わない）。
                NavigationLink(value: SocialRoute.friends) {
                    Image(systemName: "person.badge.plus")
                }
                .toolbarCircleBackground()
                .accessibilityLabel("フレンドを探す")
            }
        }
        .sheet(isPresented: $showActivity) {
            NavigationStack { SocialActivityView(userId: userId, onClose: { showActivity = false }) }
        }
        .onChange(of: showActivity) { _, shown in if !shown { Task { await refreshFeed() } } }
        .navigationDestination(for: SocialRoute.self) { route in
            switch route {
            case .friends: friendsScreen
            }
        }
        .navigationDestination(for: UserRef.self) { ref in
            UserProfileView(targetUserId: ref.id, currentUserId: userId, fallbackName: ref.name)
        }
    }

    // MARK: - Feed

    /// フィード描画コストの大きい構築(FeedBuilder＋ソート)を毎描画で行わずキャッシュする。
    /// データ件数が変わった時だけ再構築（タブ切替時の再計算ラグを排除）。
    private func rebuildFeedEntries() {
        let profilesById = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // 自分の投稿カードにも名前・アバターを出す（他人投稿とヘッダーを揃える）。
        let ownProfile = profilesById[userId]
        // 公開範囲は自分の feed_items 由来（feed_item が無い記録は未公開＝.private 表示）。
        let publishedVisibility = Dictionary(
            feedItems.lazy.filter { $0.userId == userId }.map { ($0.id, $0.visibility) },
            uniquingKeysWith: { a, _ in a })
        let ownEntries = FeedBuilder.build(
            personalRecords: prs, workouts: workouts,
            publishedVisibilityById: publishedVisibility,
            ownerName: ownProfile?.displayName ?? auth.session?.displayName,
            ownerAvatarURL: ownProfile?.avatarURL
        )
        let otherEntries = FeedBuilder.othersEntries(feedItems: feedItems, excludingUser: userId, profilesById: profilesById)
        // id 重複（自分の投稿と他者feed_itemのrefId衝突・多重ID孤児）で ForEach がアサーション落ちするのを防ぐ。
        var seen = Set<UUID>()
        feedEntries = (ownEntries + otherEntries)
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.id).inserted }
    }

    // フレンド/ランキングと容器(List)を統一してタブ切替の描画を滑らかに。重い構築はメモ化(feedEntries)。
    private var feed: some View {
        // リアクション/コメントは内容変更（種別変更=件数不変）でも即反映する必要があるため、
        // 件数キーのキャッシュは使わず描画時に直接導出する（feedEntries のような重い構築のみメモ化）。
        let reactionsByItem = Dictionary(grouping: allReactions, by: \.feedItemId)
        // コメント件数（ブロック相手のコメントは数えない）。
        let commentsByItem = Dictionary(grouping: allComments.filter { !blockedIds.contains($0.userId) }, by: \.feedItemId)
        // ブロック相手の投稿はフィードから即座に除外（App Store ガイドライン1.2「即時にフィードから消える」）。
        // blockedIds は @Query blocks 由来なので、ブロック実行で再描画され対象投稿がその場で消える。
        let blocked = blockedIds
        let visibleEntries = feedEntries.filter { $0.authorId.map { !blocked.contains($0) } ?? true }
        return List {
            ForEach(visibleEntries) { entry in
                feedRow(entry, reactions: reactionsByItem[entry.id] ?? [], commentCount: commentsByItem[entry.id]?.count ?? 0)
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
            if visibleEntries.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    EmptyStateView(systemImage: "square.stack.3d.up", title: "フィードは空です",
                                   message: "フレンドを見つけると、活動が時系列で並びます。")
                    // 遷移は値ベースに統一（クロージャ型は pushed view 上で解決されないことがある）。
                    NavigationLink(value: SocialRoute.friends) {
                        Label("フレンドを探す", systemImage: "person.badge.plus")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent).prominentLime()
                }
            }
        }
        .task(id: "\(workouts.count)-\(prs.count)-\(feedItems.count)-\(profiles.count)") { rebuildFeedEntries() }
        // カードのタップは全投稿で統一の詳細（リッチ詳細＋リアクションした人＋コメント）を開く。
        // 閉じたら編集/コメント/リアクションを反映するためフィードを作り直す。
        .onChange(of: postDetail?.id) { _, v in if v == nil { Task { await refreshFeed() } } }
        .sheet(item: $postDetail) { entry in
            PostDetailView(entry: entry, currentUserId: userId,
                           currentUserName: auth.session?.displayName,
                           onClose: { postDetail = nil })
        }
        .confirmationDialog("この記録を削除しますか？", isPresented: deleteConfirmBinding, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                guard let entry = deleteTarget else { return }
                FeedEntryDeleter.delete(entry, workouts: workouts, prs: prs, context: context, sync: sync)
                deleteTarget = nil
                Task { await refreshFeed() }
            }
            Button("キャンセル", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("投稿だけでなく記録そのものが消えます。カレンダーや分析からも無くなり、元に戻せません。投稿を取り下げるだけなら「公開範囲」を非公開にしてください。")
        }
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    /// カード（シングルタップでワークアウト詳細＋コメントを開く／ダブルタップでいいね）＋いいねバー。
    /// ワークアウトも自己ベストも同じカード仕様（矢印なし）に統一。
    private func feedRow(_ entry: FeedEntry, reactions: [PostReaction], commentCount: Int) -> some View {
        // 自分のリアクション（種別問わず1つ）。ダブルタップの二重付与防止にも使う。
        let myReaction = reactions.first { $0.userId == userId }
        return VStack(alignment: .leading, spacing: 4) {
            PostCardView(entry: entry)
                .contentShape(Rectangle())
                // ダブルタップいいねは公開済み投稿のみ（未公開＝feed_item 不在の記録に応援を付けると
                // 親不在の post_reaction が FK 違反で滞留・孤児化するため）。
                .onTapGesture(count: 2) { if entry.isPublished { doubleTapLike(entry, existing: myReaction) } }
                .onTapGesture { openEntry(entry) }
                .overlay { burstHeart(for: entry.id) }
            // 応援/コメントバーは公開済み投稿にのみ表示。未公開の自分の記録はカードのみ。
            if entry.isPublished {
                ReactionBar(feedItemId: entry.id, userId: userId, reactions: reactions,
                            commentCount: commentCount,
                            onComment: { postDetail = entry })
            }
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

    /// 投稿の長押しメニュー：自分の投稿は公開範囲の変更、他人の投稿は通報・ブロック（App Store ガイドライン1.2）。
    @ViewBuilder
    private func postMenu(_ entry: FeedEntry) -> some View {
        if !entry.isFromOther {
            Menu("公開範囲") {
                ForEach(Visibility.allCases, id: \.self) { v in
                    Button {
                        FeedPublisher.setVisibility(v, forRefId: entry.id, type: entry.feedItemType, userId: userId,
                                                    authorName: auth.session?.displayName, isPermanentAccount: auth.isPermanentAccount,
                                                    context: context, sync: sync)
                        Task { await sync.syncNow(force: true) }
                    } label: {
                        Label(v.label, systemImage: entry.visibility == v ? "checkmark" : "")
                    }
                }
            }
            // 「非公開」は投稿を取り下げるだけ。記録ごと消したいときはこちら。
            Button("削除", systemImage: "trash", role: .destructive) { deleteTarget = entry }
        } else if let authorId = entry.authorId {
            Button("通報", systemImage: "flag") {
                reportTarget = ReportUserTarget(id: authorId, displayName: displayName(for: authorId),
                                                contextType: "feed_item", contextId: entry.id)
            }
            Button("ブロック", systemImage: "hand.raised", role: .destructive) {
                blockUser(authorId, name: displayName(for: authorId))
            }
        }
    }

    // MARK: - Friends

    /// フレンド画面（検索 / フォロー中 / フォロワー）。
    /// 以前は検索がシート・フォロー一覧がこの画面と分かれていたが、相手を探す動線が
    /// 2 箇所に割れるため AddFriendView に集約した。
    private var friendsScreen: some View {
        AddFriendView(userId: userId, showsCloseButton: false)
    }
}
