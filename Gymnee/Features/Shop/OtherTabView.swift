import SwiftUI

/// 「その他」タブ（§5 ナビ）。ショップとジム管理をプルダウン（ナビバーのメニュー）で切り替える。
struct OtherTabView: View {
    let userId: UUID
    @State private var mode: Mode = .shop

    enum Mode: String, CaseIterable, Identifiable {
        case shop = "ショップ"
        case gym = "ジム管理"
        var id: String { rawValue }
        var icon: String { self == .shop ? "bag.fill" : "building.2.fill" }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .shop: ShopContent(userId: userId)
                case .gym: GymListView(userId: userId)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Picker("表示", selection: $mode) {
                            ForEach(Mode.allCases) { m in
                                Label(m.rawValue, systemImage: m.icon).tag(m)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(mode.rawValue).font(.headline)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            // ジム詳細など AppRoute 値ベース遷移先をルートで宣言。
            .gymneeNavigationDestinations(userId: userId)
        }
    }
}
