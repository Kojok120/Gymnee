import XCTest
@testable import Gymnee

/// キャラの性別（issue #141）。保存値の読み方と、選んだときの髪型の合わせ方。
final class CharacterGenderTests: XCTestCase {

    func testStoredValueFallsBackToMale() {
        XCTAssertEqual(CharacterGender(storedValue: nil), .male, "行が無い＝これまでの姿")
        XCTAssertEqual(CharacterGender(storedValue: ""), .male)
        XCTAssertEqual(CharacterGender(storedValue: "other"), .male)
        XCTAssertEqual(CharacterGender(storedValue: "female"), .female)
        XCTAssertEqual(CharacterGender(storedValue: "male"), .male)
    }

    /// 既定の髪型はどちらも無料で、実在する髪型であること（知らない id だと既定へ落ちて意図と変わる）。
    func testStarterHairsAreRealFreeStyles() {
        for gender in CharacterGender.allCases {
            let style = PixelHairArt.style(id: gender.starterHairStyleId)
            XCTAssertEqual(style.id, gender.starterHairStyleId, "\(gender) の既定の髪型が一覧に無い")
            XCTAssertFalse(style.isPaid, "\(gender) の既定の髪型が有料")
        }
        XCTAssertNotEqual(CharacterGender.male.starterHairStyleId, CharacterGender.female.starterHairStyleId)
    }

    func testChoosingGenderSwapsOnlyStarterHair() {
        // 既定のままなら選んだ性別の既定に合わせる。
        XCTAssertEqual(CharacterGender.hairAfterChoosing(.female, current: "short"), "bob")
        XCTAssertEqual(CharacterGender.hairAfterChoosing(.male, current: "bob"), "short")
        // 同じ性別を選び直しても変わらない。
        XCTAssertEqual(CharacterGender.hairAfterChoosing(.male, current: "short"), "short")
        XCTAssertEqual(CharacterGender.hairAfterChoosing(.female, current: "bob"), "bob")
        // 自分で選んだ髪型（有料・ほかの無料）は勝手に変えない。
        XCTAssertEqual(CharacterGender.hairAfterChoosing(.female, current: "ponytail"), "ponytail")
        XCTAssertEqual(CharacterGender.hairAfterChoosing(.male, current: "long"), "long")
        XCTAssertEqual(CharacterGender.hairAfterChoosing(.female, current: "buzz"), "buzz")
    }
}
