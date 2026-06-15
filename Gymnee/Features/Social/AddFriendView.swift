import SwiftUI
import SwiftData

/// フレンド追加（§6.11）。ローカルでは表示名のみの Follow を作成（実連携は Supabase 接続後）。
struct AddFriendView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalSyncEngine.self) private var sync
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("フレンド名") {
                    TextField("例: ゆうき", text: $name)
                }
                Section {
                    Text("v0 はローカル登録です。実際の相互フォローは Supabase 接続後に有効化されます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("フレンドを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("追加") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let follow = Follow(followerId: userId, followeeId: UUID(), followeeDisplayName: name.trimmingCharacters(in: .whitespaces))
        context.insert(follow)
        try? context.save()
        sync.enqueue(PendingChange(entity: "follows", recordId: follow.id, operation: .upsert, updatedAt: follow.updatedAt))
        dismiss()
    }
}
