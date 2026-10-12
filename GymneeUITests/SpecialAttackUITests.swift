import XCTest

/// 必殺技（issue #150）の通し確認。デモの戦闘画面（ソロ・戦闘中・パワー 360）で、
/// 必殺技を出す → 確認 → 再生で「必殺技」が出る → もう一度押すと「今週は使った」と出る、までを検証する。
/// 手元で `xcodebuild -scheme GymneeUITests test -only-testing:GymneeUITests/SpecialAttackUITests` で実行する。
final class SpecialAttackUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSpecialAttackOncePerWeek() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-gymneeDemo", "-gymneeScreen", "boss-solo"]
        app.launch()

        let special = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '必殺技'")).firstMatch
        XCTAssertTrue(special.waitForExistence(timeout: 15), "必殺技のボタンが出ない")
        // 開いた直後の再生が終わるまで待つ（再生中は押せない）。
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: special)
        waitForExpectations(timeout: 20)
        attach(app, "1-ready")

        special.tap()
        let confirm = app.buttons["必殺技を出す"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "確認が出ない")
        attach(app, "2-confirm")
        confirm.tap()

        let replayLine = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'あなたの 必殺技'")).firstMatch
        XCTAssertTrue(replayLine.waitForExistence(timeout: 10), "必殺技の再生が出ない")
        attach(app, "3-replay")

        // 再生を送り切ってから、もう一度押すと「今週は使った」。
        expectation(for: enabled, evaluatedWith: special)
        waitForExpectations(timeout: 20)
        special.tap()
        // 窓の言葉は 2.5 秒で消えるので、先に見る（確認が出ていないことは待たずに確かめる）。
        let used = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '今週もう つかった'")).firstMatch
        XCTAssertTrue(used.waitForExistence(timeout: 2), "今週は使ったと出ない")
        attach(app, "4-used")
        XCTAssertFalse(app.buttons["必殺技を出す"].exists, "二度目も確認が出た")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
