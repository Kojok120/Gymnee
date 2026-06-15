import SwiftUI
import SwiftData

/// カート＆チェックアウト（§6.12）。Stripe は Stub に隔離（§9-5 サブスクは保留）。
struct CartView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var checkingOut = false
    @State private var completedOrder: Order?

    private let payment: PaymentProvider = StubPaymentProvider()

    @Query private var carts: [Order]

    init(userId: UUID) {
        self.userId = userId
        let cartRaw = OrderStatus.cart.rawValue
        _carts = Query(filter: #Predicate<Order> { $0.userId == userId && $0.statusRaw == cartRaw }, sort: \Order.createdAt)
    }

    private var cart: Order? { carts.first }
    private var items: [OrderItem] { cart?.items ?? [] }

    var body: some View {
        Group {
            if let completedOrder {
                successView(completedOrder)
            } else if items.isEmpty {
                EmptyStateView(systemImage: "cart", title: "カートは空です", message: "ショップから商品を追加してください。")
            } else {
                cartList
            }
        }
        .navigationTitle("カート")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cartList: some View {
        List {
            Section {
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.product?.name ?? "商品")
                            Text(formatPrice(item.unitPrice)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Stepper("\(item.quantity)", value: bindingQty(item), in: 1...99).fixedSize()
                    }
                    .swipeActions { Button("削除", role: .destructive) { remove(item) } }
                }
            }
            Section {
                LabeledContent("合計", value: formatPrice(cart?.total ?? 0)).font(.headline)
                Button {
                    Task { await checkout() }
                } label: {
                    HStack {
                        Spacer()
                        if checkingOut { ProgressView() } else { Text("購入する（外部決済）").bold() }
                        Spacer()
                    }
                }
                .disabled(checkingOut)
            } footer: {
                Text("物理グッズは Apple IAP 対象外・外部決済です（v0 はテスト用スタブ決済）。")
            }
        }
    }

    private func successView(_ order: Order) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(Theme.energy)
            Text("購入が完了しました").font(.title2.bold())
            Text("注文番号: \(order.id.uuidString.prefix(8))").font(.caption).foregroundStyle(.secondary)
            Text(formatPrice(order.total)).font(.headline)
            Spacer()
            Button("ショップに戻る") { dismiss() }.buttonStyle(.borderedProminent).tint(Theme.energy).padding()
        }
    }

    private func bindingQty(_ item: OrderItem) -> Binding<Int> {
        Binding(get: { item.quantity }, set: { item.quantity = $0; CartStore.recomputeTotal(cart!); try? context.save() })
    }

    private func remove(_ item: OrderItem) {
        context.delete(item)
        if let cart { CartStore.recomputeTotal(cart) }
        try? context.save()
    }

    private func checkout() async {
        guard let cart else { return }
        checkingOut = true
        defer { checkingOut = false }
        do {
            let intent = try await payment.charge(amount: cart.total, currency: "JPY")
            cart.stripePaymentIntent = intent
            cart.status = .paid
            cart.updatedAt = .now
            cart.isDirty = true
            try? context.save()
            sync.enqueue(PendingChange(entity: "orders", recordId: cart.id, operation: .upsert, updatedAt: cart.updatedAt))
            completedOrder = cart
        } catch {
            // 決済失敗（Stub では起きない）。
        }
    }
}
