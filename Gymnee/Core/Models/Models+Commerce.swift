import Foundation
import SwiftData

/// 商品（§4.5 / §6.12）。
/// **コマースはアフィリエイト方式**：在庫・配送・決済は自社で持たず、提携先（楽天市場 / iHerb 等）の
/// 商品ページへ送客する。価格は提携先の値が正のため、ここでは「参考価格」として表示にのみ使う。
@Model
final class Product {
    @Attribute(.unique) var id: UUID
    var name: String
    var productDescription: String?
    /// 参考価格（円）。実価格・在庫は提携先サイトに従う。表示は「目安」として扱う。
    var price: Decimal
    var imageURL: String?
    /// 同梱アセット画像名（オフライン表示用）。
    var imageAsset: String?
    var category: String?
    var goalTags: [String]
    /// アフィリエイト遷移先（提携先の商品 / 検索ページ）。実 ASP の計測タグ付き URL を入れる。
    var affiliateURL: String?
    /// 提携先名（例: 楽天市場 / iHerb）。ステマ規制の開示表示に使用。
    var merchant: String?
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
        affiliateURL: String? = nil,
        merchant: String? = nil,
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
        self.affiliateURL = affiliateURL
        self.merchant = merchant
        self.servingsPerUnit = servingsPerUnit
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }

    /// 提携先へ遷移可能な URL（妥当な http(s) のみ）。
    var resolvedAffiliateURL: URL? {
        guard let affiliateURL, let url = URL(string: affiliateURL),
              url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }
}

/// 補給ロギング（§4.5）。在庫リマインドの根拠（§6.12）。
/// アフィリエイト方式では購入を自動検知できないため、「摂取した」のユーザーログから消費ペースを推定する。
@Model
final class SupplyLog {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var date: Date
    /// 摂取量（回数・スクープ数など）。
    var amount: Double
    /// 商品名（denormalized）。商品との突合はこれで行う。
    /// ※ 以前あった `product: Product?`（inverse 無し関連）はカタログ同期で参照先が削除されると
    ///   宙ぶらりんになり SwiftData がクラッシュしたため撤去。product_id は productName から解決する。
    var productName: String?
    var updatedAt: Date
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        userId: UUID,
        date: Date = .now,
        amount: Double = 1,
        productName: String? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.date = date
        self.amount = amount
        self.productName = productName
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

/// 有料プラン（§4.5）。採用可否は §9-5 で要決定。アフィリエイト移行後も将来のマネタイズ余地として
/// モデルのみ残置（UI / IAP 未接続）。
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
