import SwiftUI
import SwiftData

/// ユーザー検索＆フォロー（§6.11）。表示名で実ユーザー（Supabase profiles）を検索し、実 ID でフォローする。
/// バックエンド未認証時は検索不可（Sign in with Apple が必要）。
struct AddFriendView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync

    @Query private var myFollows: [Follow]
    @Query private var myBlocks: [Block]
    @State private var query = ""
    @State private var results: [SupabaseClient.RemoteProfile] = []
    @State private var searching = false
    @State private var didSearch = false
    @State private var searchError: String?
    @State private var reportTarget: ReportUserTarget?

    init(userId: UUID) {
        self.userId = userId
        _myFollows = Query(filter: #Predicate<Follow> { $0.followerId == userId })
        _myBlocks = Query(filter: #Predicate<Block> { $0.blockerId == userId })
    }

    /// 招待リンク（公式サイト。将来 App Store / ディープリンクへ差し替え）。
    private static let inviteURL = URL(string: "https://gymnee.app")!

    private var followingIds: Set<UUID> { Set(myFollows.map(\.followeeId)) }
    private var blockedIds: Set<UUID> { Set(myBlocks.map(\.blockedId)) }
    /// ブロック中のユーザーは検索結果から除外する。
    private var visibleResults: [SupabaseClient.RemoteProfile] { results.filter { !blockedIds.contains($0.id) } }

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isBackendAuthenticated {
                    notAuthenticated
                } else {
                    searchList
                }
            }
            .navigationTitle("ユーザーを探す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
            }
            .sheet(item: $reportTarget) { t in
                ReportSheet(reporterId: userId, reportedUserId: t.id, reportedDisplayName: t.displayName)
            }
        }
    }

    private var notAuthenticated: some View {
        EmptyStateView(
            systemImage: "person.crop.circle.badge.questionmark",
            title: "Sign in with Apple が必要です",
            message: "ユーザー検索と相互フォローはバックエンドにサインインすると使えます。"
        )
    }

    private var searchList: some View {
        List {
            Section {
                HStack {
                    TextField("表示名で検索", text: $query)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await runSearch() } }
                    if searching { ProgressView().controlSize(.mini) }
                    Button("検索") { Task { await runSearch() } }
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            // コールドスタート対策：知り合いをGymneeに招待する導線。
            Section {
                ShareLink(item: Self.inviteURL, message: Text("Gymneeで一緒にトレーニングを記録しよう！")) {
                    Label("友達を招待", systemImage: "person.badge.plus")
                }
            } footer: {
                Text("リンクを送って、フレンドとモチベーションを共有しましょう。")
            }

            if let searchError {
                Section {
                    Label(searchError, systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                }
            } else if didSearch && visibleResults.isEmpty && !searching {
                Section { Text("該当するユーザーが見つかりませんでした。").foregroundStyle(.secondary) }
            }

            if !visibleResults.isEmpty {
                Section("検索結果") {
                    ForEach(visibleResults) { profile in
                        HStack {
                            AvatarView(urlString: profile.avatarURL, size: 32)
                            Text(profile.displayName)
                            Spacer()
                            if followingIds.contains(profile.id) {
                                Label("フォロー中", systemImage: "checkmark")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Button("フォロー") { follow(profile) }
                                    .buttonStyle(.borderedProminent).prominentLime().controlSize(.small)
                            }
                        }
                        .swipeActions {
                            Button("ブロック", role: .destructive) {
                                Moderation.block(blockerId: userId, blockedId: profile.id, displayName: profile.displayName, context: context, sync: sync)
                            }
                        }
                        .contextMenu {
                            Button("通報", systemImage: "flag") {
                                reportTarget = ReportUserTarget(id: profile.id, displayName: profile.displayName)
                            }
                            Button("ブロック", systemImage: "hand.raised", role: .destructive) {
                                Moderation.block(blockerId: userId, blockedId: profile.id, displayName: profile.displayName, context: context, sync: sync)
                            }
                        }
                    }
                }
            }
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        searchError = nil
        defer { searching = false }
        do {
            results = try await auth.searchUsers(query: q)
        } catch {
            results = []
            searchError = "検索に失敗しました。通信状況を確認して再試行してください。"
        }
        didSearch = true
    }

    private func follow(_ profile: SupabaseClient.RemoteProfile) {
        // 同一相手の重複フォローは作らない。
        guard !followingIds.contains(profile.id) else { return }
        let follow = Follow(followerId: userId, followeeId: profile.id, followeeDisplayName: profile.displayName)
        context.insert(follow)
        // 相手プロフィールを表示用にローカル保存（フィード等でアバター/名前を引くため）。
        // 他人の profile は push できない（RLS）ので isDirty=false・enqueue しない。
        let targetId = profile.id
        let existingProfile = (try? context.fetch(FetchDescriptor<Profile>(predicate: #Predicate { $0.id == targetId })))?.first
        if let existingProfile {
            existingProfile.displayName = profile.displayName
            existingProfile.avatarURL = profile.avatarURL
            existingProfile.isDirty = false
        } else {
            let p = Profile(id: profile.id, displayName: profile.displayName, avatarURL: profile.avatarURL)
            p.isDirty = false
            context.insert(p)
        }
        try? context.save()
        sync.enqueue(PendingChange(entity: "follows", recordId: follow.id, operation: .upsert, updatedAt: follow.updatedAt))
    }
}
