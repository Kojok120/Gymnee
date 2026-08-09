import SwiftUI

/// 「その他」タブ（§5 ナビ）。プロフィール・カレンダー・ショップ・設定を大きなカードで選ぶ。
///
/// タブは iOS の上限 5 本（超えると More に畳まれる）。記録 / 分析 / 育成 / ソーシャル を
/// タブに置いた結果、カレンダーはここへ移した。外（記録のキャンセル・通知タップ）から開けるよう
/// ナビゲーションのパスは RootView が持ち、ここは受け取って使う。
struct OtherTabView: View {
    let userId: UUID
    @Binding var path: [AppRoute]

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: Theme.Spacing.lg) {
                NavigationLink(value: AppRoute.calendar) {
                    card(title: "カレンダー", subtitle: "連続記録・週の目標・予定", icon: "calendar", tint: Theme.lime)
                }
                NavigationLink(value: AppRoute.profile) {
                    card(title: "プロフィール", subtitle: "実績・マイデータ・まとめ", icon: "person.crop.circle.fill", tint: Theme.warning)
                }
                NavigationLink(value: AppRoute.shop) {
                    card(title: "ショップ", subtitle: "サプリ・ギアを探す", icon: "bag.fill", tint: Theme.series2)
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
