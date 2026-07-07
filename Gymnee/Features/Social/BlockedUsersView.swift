import SwiftUI
import SwiftData

/// ブロック中のユーザー一覧と個別解除（App Store ガイドライン1.2 の補助導線）。
/// 設定から開く。解除すると `Moderation.unblock` でサーバ `blocks` も同期削除され、
/// 相手の投稿が再びフィードに表示されるようになる（フィードは `blocks` の @Query 由来で除外している）。
struct BlockedUsersView: View {
    let currentUserId: UUID

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Query private var blocks: [Block]

    init(currentUserId: UUID) {
        self.currentUserId = currentUserId
        _blocks = Query(
            filter: #Predicate<Block> { $0.blockerId == currentUserId },
            sort: \Block.createdAt, order: .reverse
        )
    }

    var body: some View {
        List {
            ForEach(blocks) { block in
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(name(block))
                    Spacer()
                    Button("解除") { Moderation.unblock(block, context: context, sync: sync) }
                        .buttonStyle(.bordered)
                        .tint(Theme.info)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("ブロック中のユーザー")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if blocks.isEmpty {
                EmptyStateView(systemImage: "hand.raised.slash",
                               title: "ブロック中のユーザーはいません",
                               message: "ブロックしたユーザーがここに並び、いつでも解除できます。")
            }
        }
    }

    private func name(_ block: Block) -> String {
        if let n = block.blockedDisplayName, !n.isEmpty { return n }
        return "ユーザー"
    }
}
