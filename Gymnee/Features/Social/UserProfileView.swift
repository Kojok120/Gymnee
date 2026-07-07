import SwiftUI
import SwiftData
import Charts

/// フォロー中などの他ユーザーのプロフィール（§6.11）。
/// 公開投稿（feed_items）から、投稿フィード／ワークアウト集計（ヒートマップ・週次頻度）／自己ベスト一覧を
/// セグメントで切替表示する。フレンドは別ユーザーで生データは RLS で同期されないため、すべて feed_items 由来。
struct UserProfileView: View {
    let targetUserId: UUID
    let currentUserId: UUID
    let fallbackName: String

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Query private var theirFeedItems: [FeedItem]
    @Query private var profiles: [Profile]
    @Query private var myFollows: [Follow]
    @Query private var allReactions: [PostReaction]
    /// 表示中の欄（0=投稿, 1=ワークアウト, 2=自己ベスト）。
    @State private var tab = 0
    /// このユーザーの通報シート提示用（App Store ガイドライン1.2）。
    @State private var reportTarget: ReportUserTarget?
    private let calendar = Calendar.current

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
    /// feed_items は著者名を非正規化保持。profiles 行が無い相手でも名前を出せる安全網。
    private var feedName: String? {
        theirFeedItems.lazy.compactMap { $0.authorDisplayName }.first { !$0.isEmpty }
    }
    private var displayName: String {
        if let n = profile?.displayName, !n.isEmpty { return n }
        if let n = feedName { return n }
        return fallbackName
    }
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
                Picker("", selection: $tab) {
                    Text("投稿").tag(0)
                    Text("ワークアウト").tag(1)
                    Text("自己ベスト").tag(2)
                }
                .pickerStyle(.segmented)
                switch tab {
                case 1: workoutSection
                case 2: prSection
                default: postsSection
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.groupedBackground)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 他ユーザーのプロフィールから通報・ブロックできる導線（App Store ガイドライン1.2）。
            if targetUserId != currentUserId {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("通報", systemImage: "flag") {
                            reportTarget = ReportUserTarget(id: targetUserId, displayName: displayName)
                        }
                        Button("ブロック", systemImage: "hand.raised", role: .destructive) {
                            Moderation.block(blockerId: currentUserId, blockedId: targetUserId,
                                             displayName: displayName, context: context, sync: sync)
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").accessibilityLabel("その他")
                    }
                }
            }
        }
        .sheet(item: $reportTarget) { t in
            ReportSheet(reporterId: currentUserId, reportedUserId: t.id, reportedDisplayName: t.displayName,
                        contextType: t.contextType, contextId: t.contextId)
        }
    }

    // MARK: - 投稿

    @ViewBuilder
    private var postsSection: some View {
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

    // MARK: - ワークアウト（ヒートマップ＋週次頻度・直近4週）
    // フレンドの生 Workout は同期されないため、公開された .workout feed_items の日付から集計する。

    @ViewBuilder
    private var workoutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "活動ヒートマップ（直近4週）")
            HeatmapView(counts: workoutDayCounts, weeks: 4, fillWidth: true)
        }
        .gymneeCard()

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "週次頻度（直近4週）")
            if weeklyWorkoutDays.allSatisfy({ $0.count == 0 }) {
                Text("公開されたワークアウトがありません。").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(weeklyWorkoutDays) { item in
                    BarMark(x: .value("週", item.weekStart, unit: .weekOfYear),
                            y: .value("日数", item.count))
                        .foregroundStyle(Theme.energy)
                }
                .chartYScale(domain: 0...7)
                .chartYAxis { AxisMarks(values: Array(0...7)) }
                .frame(height: 160)
            }
        }
        .gymneeCard()
    }

    /// 公開ワークアウト投稿の活動日 → 件数（ヒートマップ用。HeatmapView が直近4週分だけ描画する）。
    private var workoutDayCounts: [Date: Int] {
        var counts: [Date: Int] = [:]
        for item in theirFeedItems where item.type == .workout {
            counts[calendar.startOfDay(for: item.createdAt), default: 0] += 1
        }
        return counts
    }

    private struct WeekBar: Identifiable {
        let id: Date
        let weekStart: Date
        let count: Int
    }
    /// 直近4週の各週のワークアウト日数（最大7。1日複数回でも1日）。
    private var weeklyWorkoutDays: [WeekBar] {
        let today = calendar.startOfDay(for: .now)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<4).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: start) else { return nil }
            let days = Set(theirFeedItems
                .filter { $0.type == .workout && interval.contains($0.createdAt) }
                .map { calendar.startOfDay(for: $0.createdAt) })
            return WeekBar(id: start, weekStart: start, count: min(days.count, 7))
        }
    }

    // MARK: - 自己ベスト

    @ViewBuilder
    private var prSection: some View {
        if prRows.isEmpty {
            EmptyStateView(systemImage: "trophy", title: "公開された自己ベストがありません",
                           message: "この人が自己ベストを更新するとここに並びます。")
                .padding(.top, Theme.Spacing.xl)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "自己ベストの記録")
                ForEach(prRows) { row in
                    HStack {
                        Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title).font(.subheadline)
                            Text(row.date, format: .dateTime.year().month().day())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !row.valueText.isEmpty {
                            Text(row.valueText).font(.subheadline.bold())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .gymneeCard()
        }
    }

    private struct PRRow: Identifiable {
        let id: String
        let title: String
        let valueText: String
        let date: Date
    }
    /// 公開された自己ベスト投稿を、種目ごとの「最大重量」1 行だけに絞って新しい順に並べる。
    /// 推定1RM / 最大ボリューム / 最大レップは並べず、一覧を最大重量に統一する。
    /// stats_json に数値がある投稿（改修後の発行分）は数値つき、無い旧投稿は summary をそのまま表示する。
    private var prRows: [PRRow] {
        var rows: [PRRow] = []
        for item in theirFeedItems where item.type == .pr {
            if let stats = FeedItemPRStats.decode(item.statsJSON), !stats.items.isEmpty {
                for s in stats.items {
                    guard let t = PRType(rawValue: s.type), t == .maxWeight else { continue }
                    rows.append(PRRow(
                        id: "\(item.id.uuidString)-\(s.type)",
                        title: stats.exercise,
                        valueText: t.formatted(s.value),
                        date: item.createdAt
                    ))
                }
            } else {
                rows.append(PRRow(
                    id: item.id.uuidString,
                    title: item.summary ?? "自己ベスト更新",
                    valueText: "",
                    date: item.createdAt
                ))
            }
        }
        return rows.sorted { $0.date > $1.date }
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
            // 未フォロー時は明るい lime 地 × 濃色文字（ダークで白文字が読めなくなるのを防ぐ）。
            .foregroundStyle(isFollowing ? Color.white : Theme.onLime)
            .tint(isFollowing ? Color.secondary : Theme.limeFill)

            // フォロー中のみ：このフレンドのチェックイン通知をON/OFF。
            if isFollowing, let myFollow = myFollows.first {
                Toggle(isOn: notifyBinding(myFollow)) {
                    Label("チェックイン通知を受け取る", systemImage: "bell")
                        .font(.subheadline)
                }
                .tint(Theme.lime)
                .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .gymneeCard()
    }

    private func notifyBinding(_ f: Follow) -> Binding<Bool> {
        Binding(
            get: { f.notify },
            set: { newVal in
                f.notify = newVal
                f.updatedAt = .now
                f.isDirty = true
                try? context.save()
                sync.enqueue(PendingChange(entity: "follows", recordId: f.id, operation: .upsert, updatedAt: f.updatedAt))
            }
        )
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
