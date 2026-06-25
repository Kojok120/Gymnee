import Foundation
import StoreKit
import Observation

/// Premium 課金（§4.5 / §9-5）。StoreKit2 実装。
/// 公開APIは `isPremium` / `products` / `purchase` / `restore` のみに絞り、将来 RevenueCat 実装へ
/// 差し替えても呼び出し側（機能ゲート・ペイウォール）を変えずに済むようにする（Android 展開も見据える）。
@MainActor
@Observable
final class SubscriptionService {
    /// App Store Connect で作成するサブスク商品ID（未作成だと products は空＝ペイウォールは「準備中」表示）。
    static let monthlyID = "com.gymnee.premium.monthly"
    static let yearlyID = "com.gymnee.premium.yearly"
    static var productIDs: [String] { [monthlyID, yearlyID] }

    private(set) var products: [StoreKit.Product] = []
    private(set) var isLoading = false
    private var entitled = false

    /// TestFlight/DEBUG でのプラン手動切替の保存キー。
    static let planOverrideKey = "gymnee.planOverride"

    /// プラン手動切替が使えるビルドか（DEBUG か TestFlight 配信）。本番 App Store では false。
    static var planOverrideAvailable: Bool {
        #if DEBUG
        return true
        #else
        return isTestFlight
        #endif
    }

    /// TestFlight 配信か（本番 App Store は "receipt"、TestFlight/サンドボックスは "sandboxReceipt"）。
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// プラン手動切替の値（TestFlight/DEBUG のみ有効・設定トグルと双方向バインド）。
    var planOverride: Bool = false {
        didSet { UserDefaults.standard.set(planOverride, forKey: Self.planOverrideKey) }
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    /// Premium 権限があるか（機能ゲートはこれだけを見る）。
    /// TestFlight/DEBUG では設定トグル(planOverride)が優先。本番は実際の購入権限。
    var isPremium: Bool {
        if Self.planOverrideAvailable { return planOverride }
        return entitled
    }

    init() {
        planOverride = UserDefaults.standard.bool(forKey: Self.planOverrideKey)
        // 別端末購入・更新・返金などのトランザクション更新を購読。
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let txn) = update {
                    await txn.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    deinit { updatesTask?.cancel() }

    /// 起動時などに商品取得＋権限同期。
    func bootstrap() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        products = ((try? await StoreKit.Product.products(for: Self.productIDs)) ?? [])
            .sorted { ($0.price) < ($1.price) }
    }

    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result, txn.revocationDate == nil,
               Self.productIDs.contains(txn.productID) {
                active = true
            }
        }
        entitled = active
    }

    @discardableResult
    func purchase(_ product: StoreKit.Product) async -> Bool {
        guard let result = try? await product.purchase() else { return false }
        switch result {
        case .success(let verification):
            if case .verified(let txn) = verification {
                await txn.finish()
                await refreshEntitlements()
                return isPremium
            }
            return false
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }
}
