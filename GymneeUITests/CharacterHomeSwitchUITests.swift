import XCTest

/// 育成タブの「育成 / ボス」の切り替え（issue #143）の通し確認。
/// 上の切り替えで部屋と戦闘画面を行き来できること、部屋の赤いボタンでもボスに切り替わること、
/// アプリを開き直しても最後に開いていた画面が出ること、を検証する。
///
/// デモのパーティ（ソロ・戦闘中）を読む `-gymneeScreen character-tab-boss` を使う。
/// 手元で `xcodebuild -scheme GymneeUITests test -only-testing:GymneeUITests/CharacterHomeSwitchUITests` で実行する。
final class CharacterHomeSwitchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSwitchesBetweenRoomAndBoss() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-gymneeDemo", "-gymneeScreen", "character-tab-boss"]
        app.launch()

        let room = app.buttons["page-room"]
        let boss = app.buttons["page-boss"]
        XCTAssertTrue(room.waitForExistence(timeout: 15), "育成タブの切り替えが出ない")
        dismissIntros(app)

        // 部屋。
        room.tap()
        XCTAssertTrue(room.isSelected)
        XCTAssertTrue(app.buttons["見た目"].waitForExistence(timeout: 5), "部屋が出ない")
        attach(app, "1-room")

        // 上の切り替えでボスへ。部屋は描かず、閉じるボタンも無い。
        boss.tap()
        XCTAssertTrue(boss.isSelected)
        XCTAssertFalse(room.isSelected)
        XCTAssertTrue(partyButton(app).waitForExistence(timeout: 10), "戦闘画面が出ない")
        XCTAssertFalse(app.buttons["見た目"].exists, "ボスの画面に部屋のボタンが残っている")
        XCTAssertFalse(app.buttons["閉じる"].exists, "タブの中の戦闘画面に閉じるボタンがある")
        attach(app, "2-boss")

        // 部屋に戻り、赤いボタンでもボスに切り替わる。
        room.tap()
        let banner = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'ボスに挑む'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "部屋の赤いボタンが出ない")
        banner.tap()
        XCTAssertTrue(boss.isSelected, "赤いボタンでボスに切り替わらない")
        XCTAssertTrue(partyButton(app).waitForExistence(timeout: 10))

        // 開き直しても、最後に開いていたボスの画面が出る。
        app.terminate()
        app.launch()
        let relaunchedBoss = app.buttons["page-boss"]
        XCTAssertTrue(relaunchedBoss.waitForExistence(timeout: 15))
        dismissIntros(app)
        XCTAssertTrue(relaunchedBoss.isSelected, "最後に開いていた画面を覚えていない")
        XCTAssertTrue(partyButton(app).waitForExistence(timeout: 10))
        attach(app, "3-relaunched-boss")
    }

    /// 戦闘画面の下の「パーティ」（アイコンの読み上げが付くので含むで探す）。
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
