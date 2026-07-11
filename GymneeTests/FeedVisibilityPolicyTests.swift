import XCTest
@testable import Gymnee

/// フィード投稿の公開範囲解決ルールのテスト（公開面の fail-closed 設計）。
final class FeedVisibilityPolicyTests: XCTestCase {

    func testExplicitChoiceWins() {
        // 明示選択（例: 恒久化時の private マーク・投稿メニューでの変更）は常に最優先。
        XCTAssertEqual(FeedVisibilityPolicy.resolve(
            explicitChoice: .private, existingItemVisibility: .public, defaultVisibility: .public), .private)
        XCTAssertEqual(FeedVisibilityPolicy.resolve(
            explicitChoice: .public, existingItemVisibility: .private, defaultVisibility: .friends), .public)
    }

    func testExistingItemKeepsVisibilityWithoutExplicitChoice() {
        // 明示選択が無い既存投稿は現状維持。既定値（public）で上書きしない
        // （別端末で private にした投稿が、この端末の再発行で public に巻き戻る事故の防止）。
        XCTAssertEqual(FeedVisibilityPolicy.resolve(
            explicitChoice: nil, existingItemVisibility: .private, defaultVisibility: .public), .private)
        XCTAssertEqual(FeedVisibilityPolicy.resolve(
            explicitChoice: nil, existingItemVisibility: .friends, defaultVisibility: .public), .friends)
    }

    func testNewItemUsesDefault() {
        // 新規投稿だけが既定の公開範囲を使う。
        XCTAssertEqual(FeedVisibilityPolicy.resolve(
            explicitChoice: nil, existingItemVisibility: nil, defaultVisibility: .friends), .friends)
    }
}
