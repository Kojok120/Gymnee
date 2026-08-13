import Foundation
import StoreKit
import Observation

/// アプリ内課金（非消耗型のみ）。StoreKit 2 実装。
///
/// 扱うのは**見た目だけ**（スキン / 髪型 / アクセサリー / ペット）。強さ・進化・機能には影響しない。
/// サブスクリプションは提供しない（ASC に商品が無い状態で「有料プラン」を示唆すると 2.1(b) の
/// リジェクト要因になるため、文言ごと撤去した）。
///
/// **StoreKit を import するのはこのファイルだけ**にする。View には productID の文字列と
/// 表示価格だけを渡す。SwiftData 側に同名の `Product`（アフィリエイト商品）が居るので、
/// 裸の `Product` は必ずそちらに解決される。ここでは `StoreProduct` 別名で書く。
@MainActor
@Observable
final class StoreService {

    private typealias StoreProduct = StoreKit.Product

    /// 表示用の所持キャッシュ。**これは真実ではなく、真実は `Transaction.currentEntitlements`**。
    /// 新規インストール直後のオフライン起動で空が返るとき、課金者の見た目が一瞬消えるのを防ぐだけの控え。
    private static let ownedCacheKey = "gymnee.store.owned"

    /// 取得済みの商品。**StoreKit 型を外に出さない**ため private のままにし、
    /// 外へは `isStoreAvailable` / `displayPrice(for:)` だけを見せる。
    private var products: [StoreProduct] = []
    private(set) var ownedProductIDs: Set<String> = []
    private(set) var isLoading = false

    /// 商品を取得できているか。false のときは購入ボタンを出さない
    /// （審査通過前・オフライン・ストアフロント未対応で商品が空になる）。
    var isStoreAvailable: Bool { !products.isEmpty }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        ownedProductIDs = Set(UserDefaults.standard.stringArray(forKey: Self.ownedCacheKey) ?? [])
        // 別端末購入・ファミリー共有・返金などのトランザクション更新を購読。
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

    /// 起動時などに商品取得＋所持同期。
    func bootstrap() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        products = ((try? await StoreProduct.products(for: StoreCatalog.allProductIDs)) ?? [])
            .sorted { $0.price < $1.price }
    }

    func refreshEntitlements() async {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result, txn.revocationDate == nil {
                owned.insert(txn.productID)
            }
        }
        // 空の読み取りは「持っていない」とは限らない（`StoreCatalog.mergeOwned` 参照）。
        ownedProductIDs = StoreCatalog.mergeOwned(previous: ownedProductIDs, latest: owned)
        UserDefaults.standard.set(Array(ownedProductIDs), forKey: Self.ownedCacheKey)
    }

    /// 所持しているか。
    ///
    /// デバッグ解錠は **「持っていることにする」だけ**で、実購入を打ち消さない。
    /// 剥奪できるオーバーライドを許すと「TestFlight で実購入が効かない」状態を作ってしまい、
    /// 外部配信での検証が意味を失う（旧 `planOverride` がまさにそれだった）。
    func isOwned(_ productID: String) -> Bool {
        if ownedProductIDs.contains(productID) { return true }
        #if DEBUG
        return debugUnlockAll
        #else
        return false
        #endif
    }

    private func product(for productID: String) -> StoreProduct? {
        products.first { $0.id == productID }
    }

    /// 表示価格。取得できていなければ nil（呼び出し側が控えの価格か「—」を出す）。
    func displayPrice(for productID: String) -> String? {
        product(for: productID)?.displayPrice
    }

    @discardableResult
    func purchase(productID: String) async -> PurchaseOutcome {
        guard let product = product(for: productID) else { return .unavailable }
        let result: StoreProduct.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            return .failed(error.localizedDescription)
        }
        switch result {
        case .success(let verification):
            guard case .verified(let txn) = verification else {
                return .failed("購入を確認できませんでした")
            }
            await txn.finish()
            await refreshEntitlements()
            return .purchased
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .failed("購入を確認できませんでした")
        }
    }

    /// 購入の復元。Apple は非消耗型に復元手段を要求する。
    /// 結果を返さないと UI が「復元しました」と嘘をつくので、件数と失敗を返す。
    @discardableResult
    func restore() async -> RestoreOutcome {
        do {
            try await AppStore.sync()
        } catch {
            return .failed(error.localizedDescription)
        }
        await refreshEntitlements()
        let count = ownedProductIDs.filter { StoreCatalog.entry(productID: $0) != nil }.count
        return count > 0 ? .restored(count: count) : .nothingToRestore
    }

    #if DEBUG
    /// DEBUG 限定の全解錠。設定の開発者セクションから切り替える。
    /// 製品ビルドにも TestFlight にも存在しない（TestFlight は実購入を検証する唯一の場なので、
    /// そこに解錠の余地を残すと検証結果が信用できなくなる）。
    static let debugUnlockKey = "gymnee.store.debugUnlockAll"
    var debugUnlockAll: Bool = UserDefaults.standard.bool(forKey: StoreService.debugUnlockKey) {
        didSet { UserDefaults.standard.set(debugUnlockAll, forKey: Self.debugUnlockKey) }
    }
    #endif
}

enum PurchaseOutcome: Equatable, Sendable {
    case purchased
    case cancelled
    /// 承認待ち（ファミリー共有の購入承認など）。成功でも失敗でもない。
    case pending
    /// 商品を取得できていない（審査通過前・オフライン）。
    case unavailable
    case failed(String)
}

enum RestoreOutcome: Equatable, Sendable {
    case restored(count: Int)
    case nothingToRestore
    case failed(String)
}
