import SwiftUI

/// 「その他」タブ（§5 ナビ）。Duolingo の「…」メニューのように、ジム・ショップなどを一覧から開く。
struct OtherTabView: View {
    let userId: UUID

    private enum Dest: Hashable { case shop, gym }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: Dest.shop) { menuRow("ショップ", icon: "bag.fill", tint: Theme.lime) }
                    NavigationLink(value: Dest.gym) { menuRow("ジム管理", icon: "building.2.fill", tint: Theme.energy) }
                }
            }
            .navigationTitle("その他")
            .navigationDestination(for: Dest.self) { dest in
                switch dest {
                case .shop:
                    ShopContent(userId: userId)
                        .navigationTitle("ショップ").navigationBarTitleDisplayMode(.inline)
                case .gym:
                    GymListView(userId: userId)
                }
            }
            // ジム詳細など AppRoute 値ベース遷移をルートで宣言。
            .gymneeNavigationDestinations(userId: userId)
        }
    }

    private func menuRow(_ title: String, icon: String, tint: Color) -> some View {
        Label {
            Text(title).font(.body).foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
        .padding(.vertical, 6)
    }
}
