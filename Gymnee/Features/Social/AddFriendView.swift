import SwiftUI
import SwiftData

/// フレンド画面（検索 / フォロー中 / フォロワー）。
///
/// Twitter・Instagram と同じ形に揃えている: **常設の検索バー**＋入力に追従する結果、
/// そして「フォロー中 / フォロワー」の切替。以前は検索がシート、フォロー一覧が別 push と
/// 分かれていて、相手を探す動線が 2 箇所に割れていた。
struct AddFriendView: View {
    let userId: UUID
    /// push で使うときはツールバーの「閉じる」を出さない。
    var showsCloseButton = true

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync

    @Query private var myFollows: [Follow]
    @Query private var myBlocks: [Block]
    @Query private var profiles: [Profile]

    @State private var tab: Tab = .search
    @State private var query = ""
    @State private var results: [SupabaseClient.RemoteProfile] = []
    @State private var searching = false
    @State private var didSearch = false
    @State private var searchError: String?
    @State private var reportTarget: ReportUserTarget?
    @State private var searchTask: Task<Void, Never>?

    private enum Tab: String, CaseIterable, Identifiable {
        case search, following, followers
        var id: String { rawValue }
        var label: String {
            switch self {
            case .search: return "検索"
            case .following: return "フォロー中"
            case .followers: return "フォロワー"
            }
        }
    }

    init(userId: UUID, showsCloseButton: Bool = true) {
        self.userId = userId
        self.showsCloseButton = showsCloseButton
        // 自分が follower か followee のどちらかの関係をすべて取る（相互判定・フォロワー一覧のため）。
        _myFollows = Query(filter: #Predicate<Follow> { $0.followerId == userId || $0.followeeId == userId })
        _myBlocks = Query(filter: #Predicate<Block> { $0.blockerId == userId })
    }

    // MARK: - 導出

    private var following: [Follow] { myFollows.filter { $0.followerId == userId && !blockedIds.contains($0.followeeId) } }
    private var followers: [Follow] { myFollows.filter { $0.followeeId == userId && !blockedIds.contains($0.followerId) } }
    private var followingIds: Set<UUID> { Set(following.map(\.followeeId)) }
    private var blockedIds: Set<UUID> { Set(myBlocks.map(\.blockedId)) }
    private var visibleResults: [SupabaseClient.RemoteProfile] {
        results.filter { !blockedIds.contains($0.id) && $0.id != userId }
    }

    /// 行ごとの profiles 線形走査（O(行数×全件)）を避けるための索引。
    private var profileById: [UUID: Profile] {
        Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func name(_ id: UUID, cached: String? = nil) -> String {
        if let n = profileById[id]?.displayName, !n.isEmpty { return n }
        if let cached, !cached.isEmpty { return cached }
        return "ユーザー"
    }

    var body: some View {
        Group {
            if !auth.isPermanentAccount {
                notAuthenticated
            } else {
                list
            }
        }
        .navigationTitle("フレンド")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
            }
        }
        .sheet(item: $reportTarget) { t in
            ReportSheet(reporterId: userId, reportedUserId: t.id, reportedDisplayName: t.displayName)
        }
    }

    private var notAuthenticated: some View {
        EmptyStateView(
            systemImage: "person.crop.circle.badge.questionmark",
            title: "サインインが必要です",
            message: "ユーザー検索と相互フォローはサインインすると使えます。"
        )
    }

    private var list: some View {
        List {
            Section {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Theme.Spacing.xs, trailing: 0))
            }
            switch tab {
            case .search: searchSection
            case .following: followingSection
            case .followers: followersSection
            }
        }
        .listStyle(.insetGrouped)
        // 常設の検索バー。入力に追従して検索する（Twitter/Instagram と同じ体感）。
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "名前で検索")
        .onChange(of: query) { _, q in scheduleSearch(q) }
        .onSubmit(of: .search) { runSearchNow() }
    }

    // MARK: - 検索

    @ViewBuilder private var searchSection: some View {
        if searching {
            Section { HStack { ProgressView().controlSize(.small); Text("検索中…").foregroundStyle(.secondary) } }
        }
        if let searchError {
            Section {
                Label(searchError, systemImage: "wifi.exclamationmark").foregroundStyle(Theme.warning)
            }
        }
        if !visibleResults.isEmpty {
            Section {
                ForEach(visibleResults) { profile in
                    userRow(id: profile.id, displayName: profile.displayName, avatarURL: profile.avatarURL) {
                        followButton(id: profile.id, displayName: profile.displayName, avatarURL: profile.avatarURL)
                    }
                }
            }
        } else if didSearch && !searching && !query.trimmingCharacters(in: .whitespaces).isEmpty {
            Section { Text("該当するユーザーが見つかりませんでした。").foregroundStyle(.secondary) }
        }
        // コールドスタート対策：知り合いを Gymnee に招待する導線。
        // 招待リンク（Universal Link）は自分の id 入りで、アプリ所持者が開くと
        // 自分のプロフィール（フォローボタン付き）に直行する。未所持者にはガイドページが開く。
        Section {
            ShareLink(item: InviteLink.url(for: userId), message: Text("Gymneeで一緒にトレーニングを記録しよう！")) {
                Label("友達を招待", systemImage: "person.badge.plus")
            }
        } footer: {
            Text("リンクを送って、フレンドとモチベーションを共有しましょう。")
        }
    }

    // MARK: - フォロー中 / フォロワー

    @ViewBuilder private var followingSection: some View {
        Section {
            if following.isEmpty {
                Text("まだ誰もフォローしていません。検索から探してみましょう。").foregroundStyle(.secondary)
            } else {
                ForEach(following) { f in
                    let n = name(f.followeeId, cached: f.followeeDisplayName)
                    userRow(id: f.followeeId, displayName: n, avatarURL: profileById[f.followeeId]?.avatarURL) {
                        if followers.contains(where: { $0.followerId == f.followeeId }) {
                            Text("相互")
                                .font(.caption2.bold()).foregroundStyle(Theme.info)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Theme.info.opacity(0.15), in: Capsule())
                        }
                    }
                    .swipeActions { Button("解除", role: .destructive) { unfollow(f) } }
                }
            }
        }
    }

    @ViewBuilder private var followersSection: some View {
        Section {
            if followers.isEmpty {
                Text("まだフォロワーはいません。").foregroundStyle(.secondary)
            } else {
                ForEach(followers) { f in
                    let n = name(f.followerId)
                    userRow(id: f.followerId, displayName: n, avatarURL: profileById[f.followerId]?.avatarURL) {
                        followButton(id: f.followerId, displayName: n, avatarURL: profileById[f.followerId]?.avatarURL,
                                     followLabel: "フォローバック")
                    }
                }
            }
        }
    }

    // MARK: - 行

    /// 1 ユーザー行（アバター＋名前＋右端のアクション）。タップでプロフィールへ。
    /// 遷移は値ベース（`UserRef`）に統一する（クロージャ型 NavigationLink は List 内でハングし得るため）。
    private func userRow<Trailing: View>(
        id: UUID, displayName: String, avatarURL: String?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        NavigationLink(value: UserRef(id: id, name: displayName)) {
            HStack(spacing: Theme.Spacing.md) {
                AvatarView(urlString: avatarURL, size: 40)
                Text(displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                trailing()
            }
            .padding(.vertical, 2)
        }
        .contextMenu {
            Button("通報", systemImage: "flag") {
                reportTarget = ReportUserTarget(id: id, displayName: displayName)
            }
            Button("ブロック", systemImage: "hand.raised", role: .destructive) {
                Moderation.block(blockerId: userId, blockedId: id, displayName: displayName, context: context, sync: sync)
            }
        }
    }

    @ViewBuilder
    private func followButton(id: UUID, displayName: String, avatarURL: String?, followLabel: String = "フォロー") -> some View {
        if followingIds.contains(id) {
            Label("フォロー中", systemImage: "checkmark")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Button(followLabel) { follow(id: id, displayName: displayName, avatarURL: avatarURL) }
                .buttonStyle(.borderedProminent).prominentLime().controlSize(.small)
                // 行全体の NavigationLink にタップを奪われないようにする。
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 検索実行

    /// 入力に追従する検索（デバウンス付き）。1 文字ごとにリクエストを飛ばさない。
    private func scheduleSearch(_ raw: String) {
        searchTask?.cancel()
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = []; didSearch = false; searchError = nil; searching = false
            return
        }
        tab = .search
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(q)
        }
    }

    private func runSearchNow() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searchTask = Task { await performSearch(q) }
    }

    private func performSearch(_ q: String) async {
        searching = true
        searchError = nil
        defer { searching = false }
        do {
            let found = try await auth.searchUsers(query: q)
            guard !Task.isCancelled else { return }
            results = found
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchError = "検索に失敗しました。通信状況を確認して再試行してください。"
        }
        didSearch = true
    }

    // MARK: - フォロー

    private func follow(id: UUID, displayName: String, avatarURL: String?) {
        // 同一相手の重複フォローは作らない。
        guard !followingIds.contains(id), id != userId else { return }
        let follow = Follow(followerId: userId, followeeId: id, followeeDisplayName: displayName)
        context.insert(follow)
        // 相手プロフィールを表示用にローカル保存（フィード等でアバター/名前を引くため）。
        // 他人の profile は push できない（RLS）ので isDirty=false・enqueue しない。
        let targetId = id
        if let existing = (try? context.fetch(FetchDescriptor<Profile>(predicate: #Predicate { $0.id == targetId })))?.first {
            existing.displayName = displayName
            existing.avatarURL = avatarURL
            existing.isDirty = false
        } else {
            let p = Profile(id: id, displayName: displayName, avatarURL: avatarURL)
            p.isDirty = false
            context.insert(p)
        }
        try? context.save()
        sync.enqueue(PendingChange(entity: "follows", recordId: follow.id, operation: .upsert, updatedAt: follow.updatedAt))
    }

    private func unfollow(_ f: Follow) {
        let id = f.id
        context.delete(f)
        try? context.save()
        sync.enqueue(PendingChange(entity: "follows", recordId: id, operation: .delete, updatedAt: .now))
    }
}
