import SwiftUI
import SwiftData

/// ソーシャル（§6.11）。フィード（来店/PR/ワークアウト）と合トレ・フォロー。
/// 実マルチユーザ連携は Supabase 接続後。今回はローカルデータ＋UI＋抽象。
struct SocialFeedView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        NavigationStack {
            if let uid = auth.currentUserId {
                SocialContent(userId: uid)
            } else {
                EmptyStateView(systemImage: "person.2", title: "未ログイン")
            }
        }
    }
}

private struct SocialContent: View {
    let userId: UUID

    @Query private var visits: [Visit]
    @Query private var prs: [PersonalRecord]
    @Query private var workouts: [Workout]
    @Query private var follows: [Follow]
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.friends.rawValue

    @State private var tab = 0
    @State private var showAddFriend = false

    init(userId: UUID) {
        self.userId = userId
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId }, sort: \Visit.visitedAt, order: .reverse)
        _prs = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId }, sort: \PersonalRecord.achievedAt, order: .reverse)
        _workouts = Query(filter: #Predicate<Workout> { $0.userId == userId }, sort: \Workout.date, order: .reverse)
        _follows = Query(filter: #Predicate<Follow> { $0.followerId == userId }, sort: \Follow.createdAt)
    }

    private var defaultVisibility: Visibility { Visibility(rawValue: defaultVisibilityRaw) ?? .friends }

    var body: some View {
        Group {
            switch tab {
            case 1: friendsList
            default: feed
            }
        }
        .navigationTitle("ソーシャル")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $tab) {
                    Text("フィード").tag(0)
                    Text("フレンド").tag(1)
                }.pickerStyle(.segmented).frame(width: 200)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("公開範囲", selection: $defaultVisibilityRaw) {
                        ForEach(Visibility.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                } label: { Image(systemName: "eye") }
            }
        }
        .sheet(isPresented: $showAddFriend) { AddFriendView(userId: userId) }
    }

    // MARK: - Feed

    private var feed: some View {
        let entries = FeedBuilder.build(visits: visits, personalRecords: prs, workouts: workouts, defaultVisibility: defaultVisibility)
        return ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(entries) { entry in
                    FeedCardView(entry: entry)
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
    }

    // MARK: - Friends / 合トレ

    private var friendsList: some View {
        List {
            Section("フォロー中") {
                if follows.isEmpty {
                    Text("まだ誰もフォローしていません。").foregroundStyle(.secondary)
                } else {
                    ForEach(follows) { f in
                        Label(f.followeeDisplayName ?? "ユーザー", systemImage: "person.fill")
                    }
                }
                Button {
                    showAddFriend = true
                } label: {
                    Label("フレンドを追加", systemImage: "person.badge.plus")
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
