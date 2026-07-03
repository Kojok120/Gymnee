import XCTest
@testable import Gymnee

/// 種目別の初期表示重量・刻み（ExerciseDefaults）のテスト。
final class ExerciseDefaultsTests: XCTestCase {

    func testKnownEntries() {
        XCTAssertEqual(ExerciseDefaults.entry(for: "ベンチプレス"), .init(startWeight: 30, weightStep: 2.5))
        XCTAssertEqual(ExerciseDefaults.entry(for: "サイドレイズ"), .init(startWeight: 3, weightStep: 1))
        XCTAssertEqual(ExerciseDefaults.entry(for: "レッグプレス"), .init(startWeight: 50, weightStep: 5))
        XCTAssertEqual(ExerciseDefaults.entry(for: "ケトルベルスイング"), .init(startWeight: 12, weightStep: 4))
    }

    func testUnknownNameReturnsNil() {
        XCTAssertNil(ExerciseDefaults.entry(for: "存在しない種目"))
    }

    /// 重量計測のプリセット種目は全件レビュー値を持つ（追加漏れ検出）。
    func testEveryWeightPresetHasEntry() {
        for preset in SeedData.presetExercises where preset.measurement == .weight {
            XCTAssertNotNil(ExerciseDefaults.entry(for: preset.name), "レビュー値なし: \(preset.name)")
        }
    }

    /// 懸垂・ディップスは補助が多数派のため assisted 既定（符号付き軸で加重も記録可）。
    /// 初期中央は補助側（負値）。
    func testAssistedBodyweightPresets() {
        let byName = Dictionary(uniqueKeysWithValues: SeedData.presetExercises.map { ($0.name, $0) })
        XCTAssertEqual(byName["懸垂"]?.loadMode, .assisted)
        XCTAssertEqual(byName["ディップス"]?.loadMode, .assisted)
        XCTAssertEqual(ExerciseDefaults.entry(for: "懸垂")?.startWeight, -15)
        XCTAssertEqual(ExerciseDefaults.entry(for: "ディップス")?.startWeight, -10)
    }

    /// 片側/両側ラベルの整合（ダンベル=片側、バーベル=両側計）。
    func testWeightModeConsistency() {
        for preset in SeedData.presetExercises where preset.measurement == .weight {
            if preset.equipment == .dumbbell {
                XCTAssertEqual(preset.weightMode, .perSide, "ダンベルは片側: \(preset.name)")
            }
        }
    }
}
