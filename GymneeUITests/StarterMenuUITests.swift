import XCTest

/// はじめてのメニュー（issue #119）の通し確認。
/// 新規インストール相当の状態（ワークアウト0件）で、初期設定 → 開始ゲートのメニュー選択 →
/// 記録画面の計画タブに種目カードが並ぶ、までを検証する。各段階のスクリーンショットを添付する。
///
/// 前提: 実行前にシミュレータからアプリを削除しておく（`xcrun simctl uninstall <id> com.gymnee.app.dev` 等）。
/// 既に完了ワークアウトがある状態ではメニュー自体が出ないため、このテストはスキップする。
final class StarterMenuUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstTimeUserStartsFromStarterMenu() throws {
        let app = XCUIApplication()
        app.launch()

        // 初期設定（新規のみ）。表示名を入れて「始める」。
        let nameField = app.textFields["表示名（フレンドに表示されます）"]
        if nameField.waitForExistence(timeout: 10) {
            nameField.tap()
            nameField.typeText("テスト")
            app.buttons["始める"].tap()
        }

        let menuCard = app.buttons["全身をひと通り、マシン中心の5種目で始める"]
        guard menuCard.waitForExistence(timeout: 10) else {
            throw XCTSkip("はじめてのメニューが出ていない（完了ワークアウトがある端末）。アプリを削除してから実行する")
        }
        attach(app, "1-start-gate")
        XCTAssertTrue(app.buttons["自分で種目を選んで始める"].exists, "自分で選ぶ導線が残っていること")

        menuCard.tap()

        // 記録画面の初回説明（タップで記録）が出たら閉じる。被ったままだと裏のカードを拾ってしまう。
        let howTo = app.buttons["はじめる"]
        if howTo.waitForExistence(timeout: 5) { howTo.tap() }

        // 記録画面の計画タブ。メニューの先頭種目のカードが出ていること。
        let firstExercise = app.staticTexts["チェストプレス"].firstMatch
        XCTAssertTrue(firstExercise.waitForExistence(timeout: 10), "計画タブに種目カードが並ばない")
        XCTAssertTrue(firstExercise.isHittable, "種目カードが前面に出ていない")
        attach(app, "2-record-plan-tab")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
