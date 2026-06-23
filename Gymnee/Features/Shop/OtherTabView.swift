import SwiftUI

/// 「その他」タブ（§5 ナビ）。ショップとジムを大きなカードで選び、選択するとその画面を表示する。
/// （プロフィール/設定/マイデータはカレンダーのプロフィールから到達する。）
struct OtherTabView: View {
    let userId: UUID

    private enum Dest: Hashable { case shop, gym }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                NavigationLink(value: Dest.shop) {
                    card(title: "ショップ", subtitle: "サプリ・ギアを探す", icon: "bag.fill", tint: Theme.lime)
                }
                NavigationLink(value: Dest.gym) {
                    card(title: "ジム管理", subtitle: "通うジムを登録・管理する", icon: "building.2.fill", tint: Theme.energy)
                }
                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.bg0)
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

    private func card(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard()
    }
}
