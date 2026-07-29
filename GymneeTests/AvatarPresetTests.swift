import XCTest
@testable import Gymnee

/// プリセットアイコン（`preset://<symbol>/<colorIndex>`）の解析テスト。
/// avatar_url 列をそのまま使うため、**壊れた値でも必ず描ける**ことが要件。
final class AvatarPresetTests: XCTestCase {

    func testRoundTrip() {
        let url = AvatarPreset.urlString(symbol: "flame.fill", colorIndex: 2)
        XCTAssertEqual(url, "preset://flame.fill/2")
        let parsed = AvatarPreset.parse(url)
        XCTAssertEqual(parsed?.symbol, "flame.fill")
        XCTAssertNotNil(parsed?.color)
    }

    func testNonPresetValuesReturnNil() {
        XCTAssertNil(AvatarPreset.parse(nil))
        XCTAssertNil(AvatarPreset.parse(""))
        XCTAssertNil(AvatarPreset.parse("https://example.com/a.jpg?v=1"))
        XCTAssertNil(AvatarPreset.parse("preset:/flame.fill/1"))   // スキームが不正
    }

    func testUnknownSymbolFallsBackToFirst() {
        // 新バージョンで消えたシンボルが残っていても既定へ丸めて必ず描ける。
        let parsed = AvatarPreset.parse("preset://not.a.real.symbol/0")
        XCTAssertEqual(parsed?.symbol, AvatarPreset.symbols[0])
    }

    func testOutOfRangeColorIndexFallsBack() {
        XCTAssertNotNil(AvatarPreset.parse("preset://flame.fill/999"))
        XCTAssertNotNil(AvatarPreset.parse("preset://flame.fill/-1"))
        XCTAssertNotNil(AvatarPreset.parse("preset://flame.fill/abc"))
        XCTAssertNotNil(AvatarPreset.parse("preset://flame.fill"))   // 色指定なし
    }

    func testEmptySymbolIsRejected() {
        XCTAssertNil(AvatarPreset.parse("preset:///0"))
    }

    func testIsPresetDistinguishesPhotoURLs() {
        XCTAssertTrue(AvatarPreset.isPreset(AvatarPreset.urlString(symbol: "bolt.fill", colorIndex: 1)))
        XCTAssertFalse(AvatarPreset.isPreset("https://xyz.supabase.co/storage/v1/object/public/avatars/u/a.jpg"))
    }

    func testCatalogIsValid() {
        XCTAssertFalse(AvatarPreset.symbols.isEmpty)
        XCTAssertFalse(AvatarPreset.colors.isEmpty)
        XCTAssertEqual(Set(AvatarPreset.symbols).count, AvatarPreset.symbols.count)
    }
}
