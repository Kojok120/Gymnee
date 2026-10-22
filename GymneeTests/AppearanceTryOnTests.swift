import XCTest
@testable import Gymnee

/// 見た目の試着（issue #154）。
final class AppearanceTryOnTests: XCTestCase {
    private let wearing = AppearanceTryOn(skinId: "default", hairId: "short", accessoryId: "none", petId: PetCatalog.noneId)

    func testWithoutTrialShowsWhatIsWorn() {
        XCTAssertEqual(wearing.applying(nil), wearing)
    }

    func testTrialReplacesOnlyItsKind() {
        let hair = wearing.applying(.init(kind: .hair, id: "long"))
        XCTAssertEqual(hair.hairId, "long")
        XCTAssertEqual(hair.skinId, "default")
        XCTAssertEqual(hair.accessoryId, "none")
        XCTAssertEqual(wearing.applying(.init(kind: .skin, id: "midnight")).skinId, "midnight")
        XCTAssertEqual(wearing.applying(.init(kind: .accessory, id: "shades")).accessoryId, "shades")
        XCTAssertEqual(wearing.applying(.init(kind: .pet, id: "shiba")).petId, "shiba")
    }

    func testPressingTheSameTrialAgainStopsIt() {
        let long = AppearanceTryOn.Trial(kind: .hair, id: "long")
        let pony = AppearanceTryOn.Trial(kind: .hair, id: "ponytail")
        XCTAssertEqual(AppearanceTryOn.toggled(nil, with: long), long)
        XCTAssertNil(AppearanceTryOn.toggled(long, with: long))
        XCTAssertEqual(AppearanceTryOn.toggled(long, with: pony), pony, "別のものを押したら差し替える")
    }
}
