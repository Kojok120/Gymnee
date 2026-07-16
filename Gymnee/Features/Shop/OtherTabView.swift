import SwiftUI

/// 「その他」タブ（§5 ナビ）。ショップ・設定を大きなカードで選ぶ。
/// （プロフィール/マイデータはカレンダーのプロフィールから到達する。）
struct OtherTabView: View {
    let userId: UUID

    private enum Dest: Hashable { case shop }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                NavigationLink(value: Dest.shop) {
                    card(title: "ショップ", subtitle: "サプリ・ギアを探す", icon: "bag.fill", tint: Theme.lime)
                }
                NavigationLink(value: AppRoute.settings) {
                    card(title: "設定", subtitle: "通知・目標・アカウント", icon: "gearshape.fill", tint: Theme.info)
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
                }
            }
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
