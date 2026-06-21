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
    @State private var query = ""
    @State private var results: [SupabaseClient.RemoteProfile] = []
    @State private var searching = false
    @State private var didSearch = false

    init(userId: UUID) {
        self.userId = userId
        _myFollows = Query(filter: #Predicate<Follow> { $0.followerId == userId })
    }

    private var followingIds: Set<UUID> { Set(myFollows.map(\.followeeId)) }

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

            if didSearch && results.isEmpty && !searching {
                Section { Text("該当するユーザーが見つかりませんでした。").foregroundStyle(.secondary) }
            }

            if !results.isEmpty {
                Section("検索結果") {
                    ForEach(results) { profile in
                        HStack {
                            Image(systemName: "person.circle.fill").foregroundStyle(Theme.energy)
                            Text(profile.displayName)
                            Spacer()
                            if followingIds.contains(profile.id) {
                                Label("フォロー中", systemImage: "checkmark")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Button("フォロー") { follow(profile) }
                                    .buttonStyle(.borderedProminent).tint(Theme.energy).controlSize(.small)
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
        defer { searching = false }
        results = await auth.searchUsers(query: q)
        didSearch = true
    }

    private func follow(_ profile: SupabaseClient.RemoteProfile) {
        // 同一相手の重複フォローは作らない。
        guard !followingIds.contains(profile.id) else { return }
        let follow = Follow(followerId: userId, followeeId: profile.id, followeeDisplayName: profile.displayName)
        context.insert(follow)
        try? context.save()
        sync.enqueue(PendingChange(entity: "follows", recordId: follow.id, operation: .upsert, updatedAt: follow.updatedAt))
    }
}
