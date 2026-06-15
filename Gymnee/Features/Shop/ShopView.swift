import SwiftUI

/// ショップ（§6.12）。P7 で商品一覧・カート・補給ロギング→在庫リマインドを実装する。
struct ShopView: View {
    var body: some View {
        NavigationStack {
            ComingSoonView(title: "ショップ", systemImage: "bag.fill", note: "P7 で商品・カート・補給ロギング→在庫リマインドを実装します。")
                .navigationTitle("ショップ")
        }
    }
}
