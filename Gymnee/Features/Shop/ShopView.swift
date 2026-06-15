import SwiftUI
import SwiftData

/// ショップ（§6.12）。商品一覧・ゴール連動レコメンド・在庫リマインド・カート・注文履歴。
struct ShopView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        NavigationStack {
            if let uid = auth.currentUserId {
                ShopContent(userId: uid)
            } else {
                EmptyStateView(systemImage: "bag", title: "未ログイン")
            }
        }
    }
}

private struct ShopContent: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Query(sort: \Product.name) private var products: [Product]
    @Query private var supplyLogs: [SupplyLog]
    @Query private var orders: [Order]
    @AppStorage("gymnee.goal") private var goal = "maintain"
    @State private var cartCount = 0

    private let goals: [(key: String, label: String)] = [
        ("bulk", "増量"), ("cut", "減量"), ("maintain", "維持"), ("strength", "筋力"),
    ]

    init(userId: UUID) {
        self.userId = userId
        _supplyLogs = Query(filter: #Predicate<SupplyLog> { $0.userId == userId })
        _orders = Query(filter: #Predicate<Order> { $0.userId == userId })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                goalPicker
                if !lowProducts.isEmpty { reminderCard }
                if !recommended.isEmpty { recommendSection }
                allProductsSection
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("ショップ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { OrderHistoryView(userId: userId) } label: { Image(systemName: "clock.arrow.circlepath") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CartView(userId: userId)
                } label: {
                    Image(systemName: "cart")
                        .overlay(alignment: .topTrailing) {
                            if cartCount > 0 {
                                Text("\(cartCount)").font(.caption2.bold())
                                    .padding(4).background(.red, in: Circle()).foregroundStyle(.white)
                                    .offset(x: 10, y: -10)
                            }
                        }
                }
            }
        }
        .task(id: orders.count) { cartCount = CartStore.itemCount(userId: userId, context: context) }
    }

    private var goalPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "あなたのゴール")
            Picker("ゴール", selection: $goal) {
                ForEach(goals, id: \.key) { Text($0.label).tag($0.key) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("そろそろ無くなりそう", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            ForEach(lowProducts) { product in
                HStack {
                    Text(product.name).font(.subheadline)
                    Spacer()
                    Button("購入") { addToCart(product) }
                        .buttonStyle(.borderedProminent).tint(Theme.energy).controlSize(.small)
                }
            }
        }
        .gymneeCard()
    }

    private var recommendSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "ゴールにおすすめ")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(recommended) { product in
                        NavigationLink { ProductDetailView(product: product, userId: userId) } label: {
                            productCard(product)
                        }
                        .tint(.primary)
                    }
                }
            }
        }
    }

    private var allProductsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "すべての商品")
            ForEach(products) { product in
                NavigationLink { ProductDetailView(product: product, userId: userId) } label: {
                    HStack {
                        productIcon(product)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).foregroundStyle(.primary)
                            if let cat = product.category { Text(cat).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(formatPrice(product.price)).font(.subheadline.bold())
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .gymneeCard()
    }

    private func productCard(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            productIcon(product).frame(maxWidth: .infinity)
            Text(product.name).font(.caption.bold()).lineLimit(2)
            Text(formatPrice(product.price)).font(.caption2).foregroundStyle(Theme.energy)
        }
        .frame(width: 130)
        .gymneeCard(padding: Theme.Spacing.md)
    }

    private func productIcon(_ product: Product) -> some View {
        Image(systemName: iconName(for: product.category))
            .font(.title2)
            .foregroundStyle(Theme.energy)
            .frame(width: 44, height: 44)
            .background(Theme.energy.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func iconName(for category: String?) -> String {
        switch category {
        case "プロテイン": return "drop.fill"
        case "サプリ": return "pills.fill"
        case "カーボ": return "bolt.fill"
        case "ギア": return "dumbbell.fill"
        default: return "bag.fill"
        }
    }

    private func addToCart(_ product: Product) {
        CartStore.addToCart(product: product, userId: userId, context: context, sync: sync)
        cartCount = CartStore.itemCount(userId: userId, context: context)
    }

    // MARK: - Derived

    private var recommended: [Product] {
        products.filter { $0.goalTags.contains(goal) }
    }

    private var purchasedUnits: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for order in orders where order.status != .cart {
            for item in order.items {
                if let pid = item.product?.id { counts[pid, default: 0] += item.quantity }
            }
        }
        return counts
    }

    private var lowProducts: [Product] {
        products.filter { product in
            let logs = supplyLogs.filter { $0.product?.id == product.id }.map { SupplyAnalyzer.LogPoint(date: $0.date, amount: $0.amount) }
            guard !logs.isEmpty else { return false }
            let units = purchasedUnits[product.id] ?? 1
            return SupplyAnalyzer.estimate(logs: logs, servingsPerUnit: product.servingsPerUnit, unitsPurchased: units).isLow
        }
    }
}
