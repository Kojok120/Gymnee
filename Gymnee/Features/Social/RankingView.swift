import SwiftUI
import SwiftData

/// 週間XPランキング＋ストリーク（§6.11 ゲーミフィケーション）。
/// XP は今週の feed_items から算出（ワークアウト30 / 自己ベスト20 / チェックイン10）。
/// ランキングは「自分＋フォロー中（見えている投稿の人）」のリーグ。
struct RankingView: View {
    let userId: UUID

    @AppStorage("gymnee.avatarURL") private var myAvatarURL = ""
    @Query private var feedItems: [FeedItem]
    @Query private var profiles: [Profile]
    @Query private var follows: [Follow]
    @Query private var myVisits: [Visit]
    /// 集計済みランキング（描画ごとの再計算を避けるためデータ件数変化時だけ作り直す）。
    @State private var ranks: [Rank] = []

    init(userId: UUID) {
        self.userId = userId
        _follows = Query(filter: #Predicate<Follow> { $0.followerId == userId })
        _myVisits = Query(filter: #Predicate<Visit> { $0.userId == userId })
    }

    /// 空文字を nil 扱いにする（プロフィール表示名が "" の時に「ユーザー」へ正しくフォールバックさせる）。
    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    private static func xp(for type: FeedItemType) -> Int {
        switch type {
        case .workout: return 30
        case .pr: return 20
        case .visit: return 10
        }
    }

    /// 今週の起点（毎週月曜0時にリセット）。
    private var weekStart: Date {
        var cal = Calendar.current
        cal.firstWeekday = 2 // 月曜始まり
        return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }

    private var myStreak: Int { StreakCalculator.currentStreak(visitDays: myVisits.map(\.visitedAt)) }

    private struct Rank: Identifiable {
        let id: UUID
        let name: String
        let avatarURL: String?
        let xp: Int
        let isMe: Bool
    }

    /// ランキングを集計する（`.task` から呼び、結果を `ranks` にキャッシュする）。
    private func computedRanking() -> [Rank] {
        let start = weekStart
        var xpByUser: [UUID: Int] = [:]
        for item in feedItems where item.createdAt >= start {
            xpByUser[item.userId, default: 0] += Self.xp(for: item.type)
        }
        // 参加者 = 自分 ＋ フォロー中 ＋ 今週投稿のあった人。
        var ids = Set<UUID>([userId])
        ids.formUnion(follows.map(\.followeeId))
        ids.formUnion(xpByUser.keys)
        let profileById = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // feed_items は著者名を非正規化保持しているため、プロフィール未同期でも名前を出せる安全網。
        // （差分プロフィール同期が後追いフォロー相手の古い行を取り込まず「ユーザー」化するのを防ぐ）
        var feedNameById: [UUID: String] = [:]
        for item in feedItems {
            if let n = item.authorDisplayName, !n.isEmpty { feedNameById[item.userId] = n }
        }
        let rows = ids.map { id -> Rank in
            let isMe = id == userId
            let name = isMe ? "あなた" : (Self.nonEmpty(profileById[id]?.displayName)
                ?? feedNameById[id]
                ?? Self.nonEmpty(follows.first { $0.followeeId == id }?.followeeDisplayName)
                ?? "ユーザー")
            let avatar = isMe ? (myAvatarURL.isEmpty ? nil : myAvatarURL) : profileById[id]?.avatarURL
            return Rank(id: id, name: name, avatarURL: avatar, xp: xpByUser[id] ?? 0, isMe: isMe)
        }
        return rows.sorted { ($0.xp, $1.name) > ($1.xp, $0.name) }
    }

    var body: some View {
        // フィード/フレンドと容器(List)を統一してタブ切替を滑らかにする。
        List {
            Section {
                streakCard
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            Section("今週のランキング") {
                if ranks.count <= 1 {
                    Text("フォローすると、友達と今週のXPを競えます。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(Array(ranks.enumerated()), id: \.element.id) { index, rank in
                    rankRow(index: index, rank: rank)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .background(Theme.groupedBackground)
        // データ件数が変わった時だけ再集計（タブ常時マウントでも毎描画の再計算を避ける）。
        .task(id: "\(feedItems.count)-\(profiles.count)-\(follows.count)") { ranks = computedRanking() }
    }

    private var streakCard: some View {
        HStack(spacing: Theme.Spacing.lg) {
            stat(value: "\(myStreak)", label: "連続日数", icon: "flame.fill", tint: Theme.warning)
            stat(value: "\(ranks.first(where: { $0.isMe })?.xp ?? 0)", label: "今週のXP", icon: "bolt.fill", tint: Theme.lime)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .gymneeCard()
    }

    private func stat(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).font(.title.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func rankRow(index: Int, rank: Rank) -> some View {
        if rank.isMe {
            rowContent(index: index, rank: rank)
        } else {
            // 自分以外はタップでユーザー詳細へ（値ベース遷移）。
            // List 既定のシェブロンを隠し、「あなた」行と同じ見た目にする（透明 NavigationLink を重ねるだけ）。
            ZStack {
                rowContent(index: index, rank: rank)
                NavigationLink(value: UserRef(id: rank.id, name: rank.name)) { EmptyView() }
                    .opacity(0)
            }
        }
    }

    private func rowContent(index: Int, rank: Rank) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("\(index + 1)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(index < 3 ? Theme.lime : Theme.textTertiary)
                .frame(width: 28)
            AvatarView(urlString: rank.avatarURL, size: 36)
            Text(rank.name).font(.subheadline.weight(rank.isMe ? .bold : .regular))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: Theme.Spacing.sm)
            Text("\(rank.xp) XP").font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.energy)
                .lineLimit(1).layoutPriority(1)
        }
        .padding(.vertical, 6).padding(.horizontal, Theme.Spacing.md)
        .background(rank.isMe ? Theme.limeSoft : Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
