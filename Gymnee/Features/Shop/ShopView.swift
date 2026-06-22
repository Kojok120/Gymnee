import SwiftUI
import SwiftData
import UIKit

/// ショップ（§6.12）。**アフィリエイト方式**：商品一覧・ゴール連動レコメンド・在庫リマインドを提示し、
/// 各商品は提携先サイト（楽天市場 / iHerb 等）へ送客する。カート・決済・注文は持たない。
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
    @Environment(NotificationService.self) private var notifications
    @Query(sort: \Product.name) private var products: [Product]
    @Query private var supplyLogs: [SupplyLog]
    @AppStorage("gymnee.goal") private var goal = "maintain"

    private let goals: [(key: String, label: String)] = [
        ("bulk", "増量"), ("cut", "減量"), ("maintain", "維持"), ("strength", "筋力"),
    ]

    init(userId: UUID) {
        self.userId = userId
        _supplyLogs = Query(filter: #Predicate<SupplyLog> { $0.userId == userId })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                AffiliateDisclosure()
                    .padding(.horizontal, Theme.Spacing.sm)
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
        .task(id: supplyLogs.count) {
            for product in lowProducts { notifications.notifySupplyLow(productId: product.id, productName: product.name) }
        }
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
                NavigationLink { ProductDetailView(product: product, userId: userId) } label: {
                    HStack {
                        Text(product.name).font(.subheadline).foregroundStyle(.primary)
                        Spacer()
                        Text("見る").font(.caption.bold()).foregroundStyle(Theme.energy)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
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
            SectionHeader(title: "すべての商品（\(goalLabel(goal))順）")
            ForEach(sortedProducts) { product in
                NavigationLink { ProductDetailView(product: product, userId: userId) } label: {
                    HStack {
                        productThumbnail(product, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(product.name).foregroundStyle(.primary)
                                if goalAffinity(product).contains(goal) { goalBadge }
                            }
                            if let merchant = product.merchant {
                                Text(merchant).font(.caption).foregroundStyle(.secondary)
                            } else if let cat = product.category {
                                Text(cat).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(formatReferencePrice(product.price)).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .gymneeCard()
    }

    private var goalBadge: some View {
        Text("ゴール向け")
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.energy.opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.energy)
    }

    private func goalLabel(_ key: String) -> String {
        goals.first { $0.key == key }?.label ?? key
    }

    private func productCard(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            productThumbnail(product, size: 106).frame(maxWidth: .infinity)
            Text(product.name).font(.caption.bold()).lineLimit(2)
            Text(formatReferencePrice(product.price)).font(.caption2).foregroundStyle(Theme.energy)
        }
        .frame(width: 130)
        .gymneeCard(padding: Theme.Spacing.md)
    }

    /// 商品サムネイル。画像（imageURL / imageAsset）があれば表示し、無ければカテゴリアイコンにフォールバック。
    @ViewBuilder
    private func productThumbnail(_ product: Product, size: CGFloat = 44) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.sm)
        if let urlString = product.imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    productIcon(product, size: size)
                default:
                    ZStack { Color.secondary.opacity(0.1); ProgressView().controlSize(.small) }
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .clipShape(shape)
        } else if let asset = product.imageAsset, !asset.isEmpty, UIImage(named: asset) != nil {
            Image(asset).resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipped()
                .clipShape(shape)
        } else {
            productIcon(product, size: size)
        }
    }

    private func productIcon(_ product: Product, size: CGFloat = 44) -> some View {
        Image(systemName: iconName(for: product.category))
            .font(size >= 80 ? .largeTitle : .title2)
            .foregroundStyle(Theme.energy)
            .frame(width: size, height: size)
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

    // MARK: - Derived

    private var recommended: [Product] {
        products.filter { goalAffinity($0).contains(goal) }
    }

    /// 全商品をゴール適合（合致を先頭）→名前で並べ替え。ゴール切替で表示順が必ず変わる。
    private var sortedProducts: [Product] {
        products.sorted { a, b in
            let am = goalAffinity(a).contains(goal), bm = goalAffinity(b).contains(goal)
            if am != bm { return am }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    /// 商品のゴール適合タグ。`goalTags` があればそれを、無ければカテゴリ/名前から推定する
    /// （リモートカタログで goal_tags が空でもゴール連動が効くようにするフォールバック）。
    private func goalAffinity(_ p: Product) -> Set<String> {
        if !p.goalTags.isEmpty { return Set(p.goalTags) }
        let name = p.name
        switch p.category {
        case "カーボ": return ["bulk"]
        case "ギア": return ["strength"]
        case "プロテイン":
            return name.contains("ソイ") ? ["cut", "maintain"] : ["bulk", "maintain"]
        case "サプリ":
            if name.contains("クレアチン") { return ["strength", "bulk"] }
            if name.contains("EAA") || name.contains("BCAA") { return ["cut", "maintain"] }
            return ["maintain", "cut"]
        default:
            return ["bulk", "cut", "maintain", "strength"] // 不明は全ゴールに表示
        }
    }

    /// 在庫リマインド（§6.12）。アフィリエイト方式では購入を検知できないため、
    /// 補給ログの消費ペースのみから「1容器を消費しきりそうか」を推定する（unitsPurchased=1 固定）。
    private var lowProducts: [Product] {
        products.filter { product in
            let logs = supplyLogs
                .filter { $0.product?.id == product.id }
                .map { SupplyAnalyzer.LogPoint(date: $0.date, amount: $0.amount) }
            guard !logs.isEmpty else { return false }
            return SupplyAnalyzer.estimate(logs: logs, servingsPerUnit: product.servingsPerUnit, unitsPurchased: 1).isLow
        }
    }
}
