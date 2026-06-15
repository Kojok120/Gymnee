import SwiftUI
import SwiftData

/// 注文履歴（§6.12）。
struct OrderHistoryView: View {
    let userId: UUID

    @Query private var orders: [Order]

    init(userId: UUID) {
        self.userId = userId
        let cartRaw = OrderStatus.cart.rawValue
        _orders = Query(
            filter: #Predicate<Order> { $0.userId == userId && $0.statusRaw != cartRaw },
            sort: \Order.createdAt, order: .reverse
        )
    }

    var body: some View {
        List {
            ForEach(orders) { order in
                Section {
                    ForEach(order.items) { item in
                        HStack {
                            Text(item.product?.name ?? "商品")
                            Spacer()
                            Text("×\(item.quantity)").foregroundStyle(.secondary)
                            Text(formatPrice(item.unitPrice * Decimal(item.quantity)))
                        }
                        .font(.subheadline)
                    }
                } header: {
                    HStack {
                        Text(order.createdAt, format: .dateTime.year().month().day())
                        Spacer()
                        Text(order.status.label)
                        Text(formatPrice(order.total)).bold()
                    }
                }
            }
        }
        .overlay {
            if orders.isEmpty {
                EmptyStateView(systemImage: "clock", title: "注文履歴がありません")
            }
        }
        .navigationTitle("注文履歴")
        .navigationBarTitleDisplayMode(.inline)
    }
}
