import XCTest

/// はじめてのメニュー（issue #119）の通し確認。
/// 新規インストール相当の状態（ワークアウト0件）で、初期設定 → 開始ゲートのメニュー選択 →
/// 記録画面の計画タブに種目カードが並ぶ → 1セット記録して完了 → 育成タブで祝い・遊び方・
/// 通知の確認が順に出る（issue #120）、までを検証する。各段階のスクリーンショットを添付する。
///
/// 前提: 実行前にシミュレータを初期化しておく（`xcrun simctl erase <id>`）。アプリの削除だけでは
/// UserDefaults のキャッシュが残り、初期設定や遊び方の説明が「表示済み」扱いになる。
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

        // 回数の中央（種目名のすぐ下の行）をタップして1セット記録する。
        firstExercise.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: 47)).tap()
        XCTAssertFalse(app.staticTexts["記録するとここに溜まります"].waitForExistence(timeout: 2),
                       "1セット記録できていない")

        // 完了 → サマリーを閉じる → 育成タブ。
        app.buttons["完了"].tap()
        app.alerts.buttons["完了する"].tap()
        let close = app.buttons["閉じる"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "完了サマリーが出ない")
        close.tap()

        // 初回完了 → 初めての育成タブ: 祝い → 遊び方 → 通知の確認 の順に、どれも欠けずに出る（#120）。
        let like = app.buttons["いいね"]
        XCTAssertTrue(like.waitForExistence(timeout: 10), "成長の祝いが出ない")
        attach(app, "3-growth-celebration")
        like.tap()

        let howToPlay = app.buttons["はじめる"]
        XCTAssertTrue(howToPlay.waitForExistence(timeout: 10), "遊び方の説明が出ない")
        attach(app, "4-character-onboarding")
        howToPlay.tap()

        let notifAlert = app.alerts["通知をオンにしますか？"]
        XCTAssertTrue(notifAlert.waitForExistence(timeout: 10), "通知の確認が出ない")
        attach(app, "5-notification-prompt")
        notifAlert.buttons["あとで"].tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
