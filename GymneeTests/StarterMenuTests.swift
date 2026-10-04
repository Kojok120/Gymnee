import XCTest
@testable import Gymnee

final class StarterMenuTests: XCTestCase {
    private let presetsByName = Dictionary(uniqueKeysWithValues: SeedData.presetExercises.map { ($0.name, $0) })

    func testAllItemsExistInPresetsWithMatchingMuscle() {
        // 計画カードは名前で種目を引き、無い名前は黙って落ちる。改名・削除をここで検出する。
        for menu in StarterMenu.menus {
            for item in menu.items {
                guard let preset = presetsByName[item.name] else {
                    XCTFail("\(menu.id) の「\(item.name)」がプリセットにありません")
                    continue
                }
                XCTAssertEqual(preset.muscle, item.muscle, "「\(item.name)」の部位がプリセットと不一致")
            }
        }
    }

    func testItemsAreRepCountedNotTimeOrCardio() {
        // 計画カードはレップで記録する。時間・有酸素の種目を混ぜると初期値が意味を持たない。
        for menu in StarterMenu.menus {
            for item in menu.items {
                let measurement = presetsByName[item.name]?.measurement
                XCTAssertTrue(measurement == .weight || measurement == .bodyweight,
                              "「\(item.name)」はレップで記録できる種目にする")
            }
        }
    }

    func testMenusHaveUniqueIdsAndNoDuplicateItems() {
        XCTAssertEqual(Set(StarterMenu.menus.map(\.id)).count, StarterMenu.menus.count)
        for menu in StarterMenu.menus {
            XCTAssertFalse(menu.items.isEmpty)
            XCTAssertEqual(Set(menu.items.map(\.name)).count, menu.items.count, "\(menu.id) に同じ種目が重複")
        }
    }

    func testShouldOfferOnlyBeforeFirstCompletedWorkout() {
        XCTAssertTrue(StarterMenu.shouldOffer(completedWorkoutCount: 0))
        XCTAssertFalse(StarterMenu.shouldOffer(completedWorkoutCount: 1))
    }

    func testDetailJSONUsesStartWeightsAndRoundTrips() throws {
        let menu = try XCTUnwrap(StarterMenu.menus.first)
        let json = StarterMenu.detailJSON(for: menu, startWeight: { $0 == "チェストプレス" ? 15 : nil })
        let decoded = PlanDetail.decode(json)
        XCTAssertEqual(decoded.map(\.name), menu.items.map(\.name))
        XCTAssertEqual(decoded.first?.weight, 15)
        XCTAssertEqual(decoded.last?.weight, 0, "初期値が引けない種目は 0（自重）")
        XCTAssertEqual(decoded.first?.muscleGroup, MuscleGroup.chest.rawValue)
        XCTAssertEqual(decoded.first?.sets, 3)
    }

    func testDetailJSONIsReadableAsAIPlanExercise() throws {
        // 既存の読み手と同じ形（AI 週計画の PlanExercise）で書けていること。
        let menu = try XCTUnwrap(StarterMenu.menus.first)
        let data = try XCTUnwrap(StarterMenu.detailJSON(for: menu)?.data(using: .utf8))
        let items = try JSONDecoder().decode([SupabaseClient.PlanExercise].self, from: data)
        XCTAssertEqual(items.count, menu.items.count)
    }
}
