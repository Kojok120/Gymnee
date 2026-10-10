import XCTest

/// キャラの性別（issue #141）の通し確認。
/// 初回案内で男性 → 女性と選び直す → 部屋の「見た目」の性別タブで女性が選択中になっている、までを検証する。
/// 選んだ性別は SwiftData に保存され、案内を閉じたあとの画面がそれを読むので、保存の経路も一緒に通る。
///
/// デモの部屋（`-gymneeDemo -gymneeScreen character-tab`）を使い、初回案内は起動引数で「未表示」にして毎回出す。
/// 手元で `xcodebuild -scheme GymneeUITests test -only-testing:GymneeUITests/CharacterGenderUITests` で実行する。
final class CharacterGenderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testChoosingFemaleInOnboardingIsSaved() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-gymneeDemo", "-gymneeScreen", "character-tab", "-gymnee.character.onboarded", "NO"]
        app.launch()

        let male = app.buttons["男性"]
        let female = app.buttons["女性"]
        XCTAssertTrue(female.waitForExistence(timeout: 15), "初回案内に性別の選択が出ない")

        // 前回の実行で女性が保存されていても通ってしまわないよう、いったん男性に戻してから選ぶ。
        male.tap()
        XCTAssertTrue(male.isSelected, "男性を選べない")
        female.tap()
        XCTAssertTrue(female.isSelected, "女性を選べない")
        XCTAssertFalse(male.isSelected)
        attach(app, "1-onboarding-female")

        app.buttons["はじめる"].tap()

        // 案内のあとに通知の確認が続くことがある。被ったままだと下のボタンを押せない。
        let later = app.alerts.buttons["あとで"]
        if later.waitForExistence(timeout: 3) { later.tap() }

        let appearance = app.buttons["見た目"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 10), "部屋の「見た目」が出ない")
        appearance.tap()
        app.buttons["性別"].tap()

        let femaleRow = app.buttons["gender-row-female"]
        XCTAssertTrue(femaleRow.waitForExistence(timeout: 5), "性別タブが出ない")
        XCTAssertEqual(femaleRow.label, "女性、選択中", "初回案内で選んだ女性が保存されていない")
        XCTAssertEqual(app.buttons["gender-row-male"].label, "男性を選ぶ")
        attach(app, "2-appearance-gender")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
