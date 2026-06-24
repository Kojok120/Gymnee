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

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    /// Premium 権限があるか（機能ゲートはこれだけを見る）。DEBUG はテスト用に強制ONできる。
    var isPremium: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "gymnee.debugPremium") { return true }
        #endif
        return entitled
    }

    init() {
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
