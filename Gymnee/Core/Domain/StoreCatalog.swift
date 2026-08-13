import Foundation

/// 課金商品と、アプリ内コンテンツ id の対応（純粋計算）。
///
/// **product id は App Store Connect で作成した瞬間に不変になる**。ここの文字列は実装ではなく
/// 仕様なので、リファクタで変えてはいけない（変えると既存購入者が所持を失い、取り返しがつかない）。
/// `StoreCatalogTests` がリテラルを金型として固定している。
///
/// 売るのは見た目だけ。強さ・進化・ステータス・機能には一切影響しない（`AppearanceSheet` の原則）。
enum StoreCatalog {

    enum Kind: String, CaseIterable, Sendable {
        case skin, hair, accessory, pet
    }

    struct Entry: Identifiable, Equatable, Sendable {
        let kind: Kind
        /// アプリ内の id（`CharacterSkin.id` / `PixelHairArt.Style.id` / `Accessory.id` / `PetCatalog.Pet.id`）。
        let contentID: String
        let productID: String
        /// 商品を取得できないときだけ出す控えの価格。`displayPrice` が取れたら常にそちらが勝つ。
        /// 円建て固定なので、日本のストアフロント以外では出さない（`priceFallbackAllowed`）。
        let fallbackPrice: String
        var id: String { productID }
    }

    /// 全商品。ASC 側の登録と 1:1 で対応する。
    ///
    /// 価格は課金未接続時代に画面に出していた金額をそのまま引き継ぐ（JPY の価格ポイントは
    /// ¥10 刻みなのでいずれも実在する）。TestFlight で見えていた金額を今さら動かさない。
    static let all: [Entry] = [
        Entry(kind: .skin, contentID: "midnight", productID: "com.gymnee.cosmetic.skin.midnight", fallbackPrice: "¥370"),
        Entry(kind: .skin, contentID: "sunset", productID: "com.gymnee.cosmetic.skin.sunset", fallbackPrice: "¥370"),
        Entry(kind: .skin, contentID: "gymnee", productID: "com.gymnee.cosmetic.skin.gymnee", fallbackPrice: "¥610"),
        Entry(kind: .hair, contentID: "ponytail", productID: "com.gymnee.cosmetic.hair.ponytail", fallbackPrice: "¥250"),
        Entry(kind: .hair, contentID: "long", productID: "com.gymnee.cosmetic.hair.long", fallbackPrice: "¥250"),
        Entry(kind: .accessory, contentID: "shades", productID: "com.gymnee.cosmetic.accessory.shades", fallbackPrice: "¥250"),
        Entry(kind: .accessory, contentID: "earphones", productID: "com.gymnee.cosmetic.accessory.earphones", fallbackPrice: "¥250"),
        Entry(kind: .pet, contentID: "shiba", productID: "com.gymnee.pet.shiba", fallbackPrice: "¥610"),
        Entry(kind: .pet, contentID: "tabby", productID: "com.gymnee.pet.tabby", fallbackPrice: "¥610"),
    ]

    static var allProductIDs: [String] { all.map(\.productID) }

    static func entry(kind: Kind, contentID: String) -> Entry? {
        all.first { $0.kind == kind && $0.contentID == contentID }
    }

    static func entry(productID: String) -> Entry? {
        all.first { $0.productID == productID }
    }

    /// 所持しているコンテンツ id。StoreKit の所持と、レガシー付与の和集合。
    ///
    /// レガシー付与は 1.4.1 より前のダミー購入（課金未接続の時代に「購入」を押すと
    /// タダで所持扱いになっていた）の名残。書き込み口は塞いだので増えないが、
    /// 当時のテスターから取り上げはしない。
    static func ownedContentIDs(storeOwned: Set<String>, legacy: Set<String>) -> Set<String> {
        var owned = legacy
        for productID in storeOwned {
            if let entry = entry(productID: productID) { owned.insert(entry.contentID) }
        }
        return owned
    }

    /// 所持集合の更新則。
    ///
    /// 空の読み取りは「持っていない」ではなく「答えられなかった」かもしれない
    /// （新規インストール直後のオフライン起動で `currentEntitlements` が空を返す）。
    /// 空を返されたら前回値を維持し、課金者の見た目が一瞬消えるのを防ぐ。
    /// 全額返金された人が見た目を持ち続ける取りこぼしは残るが、見た目の話なので偽陰性より軽い。
    static func mergeOwned(previous: Set<String>, latest: Set<String>) -> Set<String> {
        latest.isEmpty ? previous : latest
    }

    /// 円建ての控えの価格を出してよいか。日本以外に「¥400」と見せるのは誤った価格提示になる。
    static func priceFallbackAllowed(regionCode: String?) -> Bool {
        regionCode == "JP"
    }
}
