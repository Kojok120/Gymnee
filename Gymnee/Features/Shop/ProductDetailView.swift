import SwiftUI
import SwiftData

/// 商品詳細（§6.12）。カート追加・補給ロギング（在庫リマインドの根拠）。
struct ProductDetailView: View {
    let product: Product
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @State private var added = false
    @State private var logged = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Theme.energy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xl)
                    .background(Theme.energy.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.lg))

                Text(product.name).font(.title2.bold())
                Text(formatPrice(product.price)).font(.title3).foregroundStyle(Theme.energy)
                if let desc = product.productDescription {
                    Text(desc).font(.body).foregroundStyle(.secondary)
                }
                if !product.goalTags.isEmpty {
                    HStack {
                        ForEach(product.goalTags, id: \.self) { tag in
                            Text(goalLabel(tag)).font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Theme.energy.opacity(0.15), in: Capsule())
                        }
                    }
                }

                Button { addToCart() } label: {
                    Label(added ? "カートに追加しました" : "カートに追加", systemImage: added ? "checkmark" : "cart.badge.plus")
                        .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent).tint(Theme.energy)

                if product.servingsPerUnit != nil {
                    Button { logSupply() } label: {
                        Label(logged ? "補給を記録しました" : "今日摂取した（補給ログ）", systemImage: logged ? "checkmark" : "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Text("摂取を記録すると、消費ペースから在庫リマインドが届きます。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addToCart() {
        CartStore.addToCart(product: product, userId: userId, context: context, sync: sync)
        added = true
    }

    private func logSupply() {
        let log = SupplyLog(userId: userId, date: .now, amount: 1, productName: product.name, product: product)
        context.insert(log)
        try? context.save()
        sync.enqueue(PendingChange(entity: "supply_logs", recordId: log.id, operation: .upsert, updatedAt: log.updatedAt))
        logged = true
    }

    private func goalLabel(_ tag: String) -> String {
        switch tag {
        case "bulk": return "増量"
        case "cut": return "減量"
        case "maintain": return "維持"
        case "strength": return "筋力"
        default: return tag
        }
    }
}
