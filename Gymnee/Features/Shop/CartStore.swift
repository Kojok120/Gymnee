import Foundation
import SwiftData

/// カート操作（§6.12）。status=.cart の Order を 1 つ維持し、明細を出し入れする。
@MainActor
enum CartStore {
    /// 進行中のカート Order を取得（なければ作成）。
    static func cartOrder(userId: UUID, context: ModelContext) -> Order {
        let cartRaw = OrderStatus.cart.rawValue
        let descriptor = FetchDescriptor<Order>(
            predicate: #Predicate { $0.userId == userId && $0.statusRaw == cartRaw }
        )
        if let existing = (try? context.fetch(descriptor))?.first { return existing }
        let order = Order(userId: userId, status: .cart)
        context.insert(order)
        return order
    }

    static func addToCart(product: Product, quantity: Int = 1, userId: UUID, context: ModelContext, sync: LocalSyncEngine) {
        let cart = cartOrder(userId: userId, context: context)
        if let existing = cart.items.first(where: { $0.product?.id == product.id }) {
            existing.quantity += quantity
            existing.updatedAt = .now
        } else {
            let item = OrderItem(quantity: quantity, unitPrice: product.price, order: cart, product: product)
            context.insert(item)
        }
        recomputeTotal(cart)
        try? context.save()
        sync.enqueue(PendingChange(entity: "orders", recordId: cart.id, operation: .upsert, updatedAt: cart.updatedAt))
    }

    static func itemCount(userId: UUID, context: ModelContext) -> Int {
        let cartRaw = OrderStatus.cart.rawValue
        let descriptor = FetchDescriptor<Order>(
            predicate: #Predicate { $0.userId == userId && $0.statusRaw == cartRaw }
        )
        let cart = (try? context.fetch(descriptor))?.first
        return cart?.items.reduce(0) { $0 + $1.quantity } ?? 0
    }

    static func recomputeTotal(_ order: Order) {
        order.total = order.items.reduce(Decimal(0)) { $0 + $1.unitPrice * Decimal($1.quantity) }
        order.updatedAt = .now
    }
}

/// 価格表示ヘルパ（円）。
func formatPrice(_ value: Decimal) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "JPY"
    f.maximumFractionDigits = 0
    f.locale = Locale(identifier: "ja_JP")
    return f.string(from: value as NSDecimalNumber) ?? "¥\(value)"
}
