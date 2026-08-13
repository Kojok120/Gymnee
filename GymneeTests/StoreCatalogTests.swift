import XCTest
@testable import Gymnee

/// 課金商品カタログ。
///
/// **product id は App Store Connect で作成した瞬間に不変になる**。ここのアサーションは
/// リテラルの金型で、落ちたら「テストを直す」のではなく「変更をやめる」のが正しい対応。
/// product id を変えると既存購入者が所持を失い、取り返しがつかない。
final class StoreCatalogTests: XCTestCase {

    /// ASC に登録した product id そのもの。変更禁止。
    func testProductIDsAreFrozen() {
        let expected: [StoreCatalog.Kind: [String: String]] = [
            .skin: [
                "midnight": "com.gymnee.cosmetic.skin.midnight",
                "sunset": "com.gymnee.cosmetic.skin.sunset",
                "gymnee": "com.gymnee.cosmetic.skin.gymnee",
            ],
            .hair: [
                "ponytail": "com.gymnee.cosmetic.hair.ponytail",
                "long": "com.gymnee.cosmetic.hair.long",
            ],
            .accessory: [
                "shades": "com.gymnee.cosmetic.accessory.shades",
                "earphones": "com.gymnee.cosmetic.accessory.earphones",
            ],
            .pet: [
                "shiba": "com.gymnee.pet.shiba",
                "tabby": "com.gymnee.pet.tabby",
            ],
        ]
        for (kind, pairs) in expected {
            for (contentID, productID) in pairs {
                XCTAssertEqual(
                    StoreCatalog.entry(kind: kind, contentID: contentID)?.productID, productID,
                    "\(kind.rawValue)/\(contentID) の product id を変えてはいけない"
                )
            }
        }
        XCTAssertEqual(StoreCatalog.all.count, expected.values.reduce(0) { $0 + $1.count })
    }

    func testProductIDsAreUnique() {
        XCTAssertEqual(Set(StoreCatalog.allProductIDs).count, StoreCatalog.all.count)
    }

    /// contentID ↔ productID の往復。
    func testLookupRoundTrips() {
        for entry in StoreCatalog.all {
            let found = StoreCatalog.entry(productID: entry.productID)
            XCTAssertEqual(found?.contentID, entry.contentID)
            XCTAssertEqual(found?.kind, entry.kind)
        }
        XCTAssertNil(StoreCatalog.entry(productID: "com.gymnee.nope"))
        XCTAssertNil(StoreCatalog.entry(kind: .skin, contentID: "nope"))
    }

    /// 同じ contentID を別種別で引いても混ざらない（id 空間は種別ごとに別）。
    func testKindsDoNotLeakIntoEachOther() {
        XCTAssertNil(StoreCatalog.entry(kind: .hair, contentID: "midnight"))
        XCTAssertNil(StoreCatalog.entry(kind: .skin, contentID: "ponytail"))
    }

    /// 有料の見た目は必ず商品が登録されている（カタログの取りこぼし検出）。
    /// これが落ちるのは「売り物なのに買えない」状態なので、審査でも実害でも問題になる。
    func testEveryPaidCosmeticHasAProduct() {
        for skin in SkinCatalog.all where skin.isPaid {
            XCTAssertNotNil(StoreCatalog.entry(kind: .skin, contentID: skin.id), "スキン \(skin.id)")
        }
        for style in PixelHairArt.styles where style.isPaid {
            XCTAssertNotNil(StoreCatalog.entry(kind: .hair, contentID: style.id), "髪型 \(style.id)")
        }
        for accessory in PixelHairArt.accessories where accessory.isPaid {
            XCTAssertNotNil(StoreCatalog.entry(kind: .accessory, contentID: accessory.id), "アクセサリー \(accessory.id)")
        }
    }

    /// 逆向き：商品があるのにカタログに無い見た目を作らない。
    func testEveryCosmeticProductPointsAtSomethingReal() {
        for entry in StoreCatalog.all {
            switch entry.kind {
            case .skin:
                XCTAssertTrue(SkinCatalog.all.contains { $0.id == entry.contentID }, entry.productID)
            case .hair:
                XCTAssertTrue(PixelHairArt.styles.contains { $0.id == entry.contentID }, entry.productID)
            case .accessory:
                XCTAssertTrue(PixelHairArt.accessories.contains { $0.id == entry.contentID }, entry.productID)
            case .pet:
                break   // ペットは PetCatalog 側で突き合わせる
            }
        }
    }

    func testOwnedContentIDsUnionsStoreAndLegacy() {
        let owned = StoreCatalog.ownedContentIDs(
            storeOwned: ["com.gymnee.cosmetic.skin.sunset", "com.gymnee.nope"],
            legacy: ["ponytail"]
        )
        XCTAssertEqual(owned, ["sunset", "ponytail"], "未知の product id は無視する")
    }

    /// 空の読み取りは「持っていない」ではなく「答えられなかった」かもしれない。
    /// オフライン起動で課金者の見た目が消えないことを固定する。
    func testEmptyReadKeepsPreviousOwnership() {
        let previous: Set<String> = ["com.gymnee.pet.shiba"]
        XCTAssertEqual(StoreCatalog.mergeOwned(previous: previous, latest: []), previous)
    }

    /// 非空の読み取りは上書きする（返金・失効がここで反映される）。
    func testNonEmptyReadReplacesOwnership() {
        let previous: Set<String> = ["com.gymnee.pet.shiba", "com.gymnee.pet.tabby"]
        let latest: Set<String> = ["com.gymnee.pet.tabby"]
        XCTAssertEqual(StoreCatalog.mergeOwned(previous: previous, latest: latest), latest)
    }

    /// 円建ての控え価格は日本以外に出さない（誤った価格提示になる）。
    func testFallbackPriceIsJapanOnly() {
        XCTAssertTrue(StoreCatalog.priceFallbackAllowed(regionCode: "JP"))
        XCTAssertFalse(StoreCatalog.priceFallbackAllowed(regionCode: "US"))
        XCTAssertFalse(StoreCatalog.priceFallbackAllowed(regionCode: nil))
    }

    /// 控え価格は円表記で、金額が入っている。
    func testFallbackPricesLookLikeYen() {
        for entry in StoreCatalog.all {
            XCTAssertTrue(entry.fallbackPrice.hasPrefix("¥"), entry.productID)
            XCTAssertTrue(entry.fallbackPrice.dropFirst().allSatisfy(\.isNumber), entry.productID)
        }
    }
}
