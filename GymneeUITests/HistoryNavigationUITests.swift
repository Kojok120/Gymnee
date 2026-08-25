import XCTest

/// 記録一覧まわりのナビゲーション回帰テスト。
/// 開始ゲート→記録一覧→ワークアウト詳細の push が正しく積まれることを検証する。
///
/// 背景: ゲート→記録一覧がクロージャ型 NavigationLink だった時、記録一覧からの
/// 値ベース push（AppRoute.workoutDetail）がクロージャ push の下へ積まれ、
/// 「行をタップしても一覧のまま・戻るとなぜか詳細が出る」という不具合が iOS 26 で起きた。
/// スキームは GymneeUITests 単独（CI の Gymnee スキームのテストには含めない）。
final class HistoryNavigationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHistoryRowOpensWorkoutDetailAndBackReturnsToList() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-gymneeDemo"]
        app.launch()

        // 開始ゲート → これまでの記録を見る
        let historyLink = app.buttons["これまでの記録を見る"]
        XCTAssertTrue(historyLink.waitForExistence(timeout: 15), "開始ゲートの履歴導線が見つからない")
        historyLink.tap()

        let listBar = app.navigationBars["記録一覧"]
        XCTAssertTrue(listBar.waitForExistence(timeout: 5), "記録一覧が開かない")

        // 先頭のワークアウト行（デモの最新は「胸・三頭」）をタップ → 詳細へ
        let firstRow = app.staticTexts["胸・三頭"].firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "記録一覧にワークアウト行が無い")
        firstRow.tap()

        // 詳細＝ナビタイトルがワークアウト名になり、ツールバーに「編集」が出る。
        // 不具合時はここで一覧のままになり失敗する。
        let detailBar = app.navigationBars["胸・三頭"]
        XCTAssertTrue(detailBar.waitForExistence(timeout: 5), "行タップで詳細へ遷移しない（一覧のまま）")
        XCTAssertTrue(detailBar.buttons["編集"].exists, "詳細ツールバーの編集ボタンが無い")

        // 戻る → 記録一覧に戻る（不具合時は別の詳細が現れる）。
        detailBar.buttons.firstMatch.tap()
        XCTAssertTrue(listBar.waitForExistence(timeout: 5), "詳細から戻っても記録一覧に戻らない")
    }
}
