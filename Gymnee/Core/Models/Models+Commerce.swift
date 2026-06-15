import Foundation
import SwiftData

/// 商品（§4.5）。在庫管理の有無はフルフィルメント方式に依存（§9-4）。
@Model
final class Product {
    @Attribute(.unique) var id: UUID
    var name: String
    var productDescription: String?
    var price: Decimal
    var imageURL: String?
    /// 同梱アセット画像名（オフライン表示用）。
    var imageAsset: String?
    var category: String?
    var goalTags: [String]
    var stock: Int?
    /// 補給ロギングの基準量（例: 1容器あたりの回数）。在庫リマインドに使用。
    var servingsPerUnit: Int?
    var updatedAt: Date
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        name: String,
        productDescription: String? = nil,
        price: Decimal,
        imageURL: String? = nil,
        imageAsset: String? = nil,
        category: String? = nil,
        goalTags: [String] = [],
        stock: Int? = nil,
        servingsPerUnit: Int? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.name = name
        self.productDescription = productDescription
        self.price = price
        self.imageURL = imageURL
        self.imageAsset = imageAsset
        self.category = category
        self.goalTags = goalTags
        self.stock = stock
        self.servingsPerUnit = servingsPerUnit
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// 注文（§4.5）。物理グッズのため外部決済（§6.12）。
@Model
final class Order {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var statusRaw: String
    var total: Decimal
    var stripePaymentIntent: String?
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool

    @Relationship(deleteRule: .cascade, inverse: \OrderItem.order)
    var items: [OrderItem] = []

    var status: OrderStatus {
        get { OrderStatus(rawValue: statusRaw) ?? .cart }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        status: OrderStatus = .cart,
        total: Decimal = 0,
        stripePaymentIntent: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.statusRaw = status.rawValue
        self.total = total
        self.stripePaymentIntent = stripePaymentIntent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// 注文明細（§4.5）。
@Model
final class OrderItem {
    @Attribute(.unique) var id: UUID
    var quantity: Int
    var unitPrice: Decimal
    var updatedAt: Date
    var isDirty: Bool

    var order: Order?
    var product: Product?

    init(
        id: UUID = UUID(),
        quantity: Int,
        unitPrice: Decimal,
        order: Order? = nil,
        product: Product? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.order = order
        self.product = product
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// 補給ロギング（§4.5）。在庫リマインドの根拠（§6.12）。
@Model
final class SupplyLog {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var date: Date
    /// 摂取量（回数・スクープ数など）。
    var amount: Double
    var productName: String?
    var updatedAt: Date
    var isDirty: Bool

    var product: Product?

    init(
        id: UUID = UUID(),
        userId: UUID,
        date: Date = .now,
        amount: Double = 1,
        productName: String? = nil,
        product: Product? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.date = date
        self.amount = amount
        self.productName = productName
        self.product = product
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// 有料プラン（§4.5）。採用可否は §9-5 で要決定。
@Model
final class Subscription {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var tierRaw: String
    var statusRaw: String
    var startedAt: Date
    var updatedAt: Date
    var isDirty: Bool

    var tier: SubscriptionTier {
        get { SubscriptionTier(rawValue: tierRaw) ?? .free }
        set { tierRaw = newValue.rawValue }
    }

    var status: SubscriptionStatus {
        get { SubscriptionStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        tier: SubscriptionTier = .free,
        status: SubscriptionStatus = .active,
        startedAt: Date = .now,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.tierRaw = tier.rawValue
        self.statusRaw = status.rawValue
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
