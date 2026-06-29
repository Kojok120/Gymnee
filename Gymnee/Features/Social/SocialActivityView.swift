import SwiftUI
import SwiftData

/// 通知一覧（§6.11）。自分の投稿に付いた他者の「いいね/応援（PostReaction）」「コメント（Comment）」を
/// 投稿ごとにまとめて新しい順に並べる（Twitter 風）。「自分の投稿」画面の右上ベルから push で開く。
/// 開いた時点で既読化（lastSeen を now にして両バッジを消す）。行タップで該当投稿の詳細を開く。
struct SocialActivityView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync

    @Query private var allReactions: [PostReaction]
    @Query private var allComments: [Comment]
    @Query private var blocks: [Block]
    @Query private var profiles: [Profile]
    @Query private var feedItems: [FeedItem]
    @Query private var visits: [Visit]
    @Query private var prs: [PersonalRecord]
    @Query private var workouts: [Workout]
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.friends.rawValue
    @AppStorage(SocialActivityBuilder.lastSeenDefaultsKey) private var lastSeenRaw = 0.0

    /// 開いた瞬間に既読化するが、未読ドットは「開く前の lastSeen」基準で描くためのスナップショット。
    @State private var renderSince: Double?
    /// タップで開く投稿詳細。
    @State private var postDetail: FeedEntry?
    @State private var visStore = PostVisibilityStore()

    init(userId: UUID) {
        self.userId = userId
        _blocks = Query(filter: #Predicate<Block> { $0.blockerId == userId })
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId }, sort: \Visit.visitedAt, order: .reverse)
        _prs = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId }, sort: \PersonalRecord.achievedAt, order: .reverse)
        _workouts = Query(filter: #Predicate<Workout> { $0.userId == userId }, sort: \Workout.date, order: .reverse)
    }

    private var defaultVisibility: Visibility { Visibility(rawValue: defaultVisibilityRaw) ?? .public }
    private var blockedIds: Set<UUID> { Set(blocks.map(\.blockedId)) }
    /// 反応/コメントが参照する自分の投稿（feed_item）の id 集合。
    private var myPostIds: Set<UUID> { Set(feedItems.filter { $0.userId == userId }.map(\.id)) }

    /// 自分の投稿への他者反応（新しい順）→ 投稿ごとに集約。
    private var groups: [SocialActivityGroup] {
        let activities = SocialActivityFeed.build(reactions: allReactions, comments: allComments,
                                                  myPostIds: myPostIds, currentUserId: userId, blockedIds: blockedIds)
        return SocialActivityBuilder.group(activities)
    }

    /// 自分の投稿の FeedEntry（詳細遷移用）。FeedItem.id == FeedEntry.id なので postId で引ける。
    private var entriesById: [UUID: FeedEntry] {
        let entries = FeedBuilder.build(visits: visits, personalRecords: prs, workouts: workouts,
                                        defaultVisibility: defaultVisibility, visibilityStore: visStore)
        return Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let since = Date(timeIntervalSince1970: renderSince ?? lastSeenRaw)
        List {
            ForEach(groups) { group in
                row(group, unread: group.latestDate > since)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .background(Theme.groupedBackground)
        .overlay {
            if groups.isEmpty {
                EmptyStateView(systemImage: "bell",
                               title: "通知はありません",
                               message: "あなたの投稿にいいねや応援、コメントが付くとここに表示されます。")
            }
        }
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 開く前の lastSeen を一度だけ控えてから既読化する（未読ドットは控えた値で描く）。
            if renderSince == nil { renderSince = lastSeenRaw }
            lastSeenRaw = Date.now.timeIntervalSince1970
            await ensureProfiles()
        }
        .sheet(item: $postDetail) { entry in
            PostDetailView(entry: entry, currentUserId: userId, onClose: { postDetail = nil })
        }
    }

    // MARK: - 行（投稿ごと集約）

    @ViewBuilder
    private func row(_ group: SocialActivityGroup, unread: Bool) -> some View {
        let entry = entriesById[group.postId]
        Button {
            if let entry { postDetail = entry }
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                avatarCluster(group.actorIds)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline(group))
                        .font(.subheadline).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let entry {
                        Label(entry.title, systemImage: entry.icon)
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    if let text = group.latestCommentText, !text.isEmpty {
                        Text("“\(text)”").font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                    Text(group.latestDate, format: .relative(presentation: .named))
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                if unread { Circle().fill(Theme.lime).frame(width: 8, height: 8).padding(.top, 6) }
            }
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(entry == nil)
    }

    /// 反応者アバターを最大 3 人重ねて表示。
    private func avatarCluster(_ ids: [UUID]) -> some View {
        HStack(spacing: -10) {
            ForEach(Array(ids.prefix(3)), id: \.self) { id in
                AvatarView(urlString: avatarURL(id), size: 36)
                    .overlay { Circle().strokeBorder(Theme.bg1, lineWidth: 2) }
            }
        }
    }

    /// 「〇〇さん 他N人が応援・コメントしました」。
    private func headline(_ group: SocialActivityGroup) -> String {
        let first = name(group.actorIds.first)
        let others = max(0, group.actorIds.count - 1)
        let who = others > 0 ? "\(first) 他\(others)人" : first
        let verb: String
        if group.reactionCount > 0 && group.commentCount > 0 {
            verb = "が応援・コメントしました"
        } else if group.reactionCount > 0 {
            verb = "が応援しました"
        } else {
            verb = "がコメントしました"
        }
        return who + verb
    }

    // MARK: - 名前/アバター解決（PostDetailView と同じ方針）

    private func name(_ id: UUID?) -> String {
        guard let id else { return "ユーザー" }
        if let n = profiles.first(where: { $0.id == id })?.displayName, !n.isEmpty { return n }
        if let n = allComments.first(where: { $0.userId == id })?.authorDisplayName, !n.isEmpty { return n }
        return "ユーザー"
    }
    private func avatarURL(_ id: UUID) -> String? { profiles.first(where: { $0.id == id })?.avatarURL }

    /// 反応者・コメント者のプロフィール（名前/アバター）が未取得なら取りに行く。
    private func ensureProfiles() async {
        var ids = Set(groups.flatMap(\.actorIds))
        ids.subtract(profiles.map(\.id))
        ids.remove(userId)
        if !ids.isEmpty { await sync.ensureProfiles(ids: ids) }
    }
}
