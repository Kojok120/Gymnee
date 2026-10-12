import XCTest

/// 育成タブの部屋と地下のボス部屋の行き来（issue #143 / #145）の通し確認。
/// 部屋の赤いボタンでボス部屋へ降り、ボス部屋の「部屋へ」で上れること、
/// アプリを開き直しても最後にいた場所から始まること、を検証する。
///
/// デモのパーティ（ソロ・戦闘中）を読む `-gymneeScreen character-tab-boss` を使う。
/// 手元で `xcodebuild -scheme GymneeUITests test -only-testing:GymneeUITests/CharacterHomeSwitchUITests` で実行する。
final class CharacterHomeSwitchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGoesDownToBossAndBackUp() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-gymneeDemo", "-gymneeScreen", "character-tab-boss"]
        app.launch()
        dismissIntros(app)

        // 前回ボス部屋で終えていたら、まず部屋に上る。
        let upstairs = app.buttons["部屋に戻る"]
        if upstairs.waitForExistence(timeout: 5) { upstairs.tap() }

        // 部屋。タブ風の切り替えは無い。
        XCTAssertTrue(app.buttons["見た目"].waitForExistence(timeout: 10), "部屋が出ない")
        XCTAssertFalse(app.buttons["page-boss"].exists, "上の切り替えが残っている")
        attach(app, "1-room")

        // 赤いボタンでボス部屋へ降りる。部屋は描かず、閉じるボタンも無い。
        let banner = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'ボスに挑む'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "部屋の赤いボタンが出ない")
        banner.tap()
        XCTAssertTrue(partyButton(app).waitForExistence(timeout: 10), "ボス部屋が出ない")
        XCTAssertTrue(upstairs.waitForExistence(timeout: 5), "ボス部屋に「部屋へ」が無い")
        XCTAssertFalse(app.buttons["見た目"].exists, "ボス部屋に部屋のボタンが残っている")
        XCTAssertFalse(app.buttons["閉じる"].exists, "ボス部屋に閉じるボタンがある")
        attach(app, "2-boss")

        // 開き直しても、最後にいたボス部屋から始まる。
        app.terminate()
        app.launch()
        dismissIntros(app)
        XCTAssertTrue(partyButton(app).waitForExistence(timeout: 15), "最後にいた場所を覚えていない")
        attach(app, "3-relaunched-boss")

        // 「部屋へ」で部屋に上る。
        app.buttons["部屋に戻る"].tap()
        XCTAssertTrue(app.buttons["見た目"].waitForExistence(timeout: 10), "部屋に上れない")
        XCTAssertFalse(app.buttons["部屋に戻る"].exists)
        attach(app, "4-back-in-room")
    }

    /// ボス部屋の下の「パーティ」（アイコンの読み上げが付くので含むで探す）。
    private func partyButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'パーティ'")).firstMatch
    }

    /// 通知の確認が被っていたら閉じる（端末の状態によって出る）。
    private func dismissIntros(_ app: XCUIApplication) {
        let later = app.alerts.buttons["あとで"]
        if later.waitForExistence(timeout: 2) { later.tap() }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
