import XCTest
@testable import Gymnee

/// 種目別の初期表示重量・刻み（ExerciseDefaults）のテスト。
final class ExerciseDefaultsTests: XCTestCase {

    func testKnownEntries() {
        XCTAssertEqual(ExerciseDefaults.entry(for: "ベンチプレス"), .init(startWeight: 30, weightStep: 2.5))
        XCTAssertEqual(ExerciseDefaults.entry(for: "サイドレイズ"), .init(startWeight: 3, weightStep: 1))
        XCTAssertEqual(ExerciseDefaults.entry(for: "レッグプレス"), .init(startWeight: 50, weightStep: 5))
        XCTAssertEqual(ExerciseDefaults.entry(for: "ケトルベルスイング"), .init(startWeight: 12, weightStep: 4))
        // issue #114: ケーブル片側は 1.25kg 刻み。
        XCTAssertEqual(ExerciseDefaults.entry(for: "ケーブルサイドレイズ"), .init(startWeight: 5, weightStep: 1.25))
        XCTAssertEqual(ExerciseDefaults.entry(for: "ケーブルクロスオーバー"), .init(startWeight: 5, weightStep: 1.25))
    }

    func testUnknownNameReturnsNil() {
        XCTAssertNil(ExerciseDefaults.entry(for: "存在しない種目"))
    }

    // MARK: - 器具既定（カスタム種目のフォールバック・純粋関数）

    /// ケーブルは片側なら 1.25kg（ファンクショナルトレーナーの実効刻み）、それ以外はスタック 5kg。
    func testFallbackStepCable() {
        XCTAssertEqual(ExerciseDefaults.fallbackStep(equipment: .cable, weightMode: .perSide), 1.25)
        XCTAssertEqual(ExerciseDefaults.fallbackStep(equipment: .cable, weightMode: .none), 5)
        XCTAssertEqual(ExerciseDefaults.fallbackStep(equipment: .cable, weightMode: .both), 5)
    }

    /// 片側指定はケーブル以外の刻みを変えない（マシン片側=プレートロード等は従来どおり）。
    func testFallbackStepOtherEquipment() {
        for mode in WeightMode.allCases {
            XCTAssertEqual(ExerciseDefaults.fallbackStep(equipment: .machine, weightMode: mode), 5)
            XCTAssertEqual(ExerciseDefaults.fallbackStep(equipment: .kettlebell, weightMode: mode), 4)
            XCTAssertEqual(ExerciseDefaults.fallbackStep(equipment: .dumbbell, weightMode: mode), 1)
            XCTAssertEqual(ExerciseDefaults.fallbackStep(equipment: .barbell, weightMode: mode), 2.5)
            XCTAssertEqual(ExerciseDefaults.fallbackStep(equipment: .bodyweight, weightMode: mode), 2.5)
            XCTAssertEqual(ExerciseDefaults.fallbackStep(equipment: .other, weightMode: mode), 2.5)
        }
    }

    func testFallbackStartWeight() {
        // ケーブル片側は片手分なので控えめ（5kg）、両手/指定なしは 10kg。
        XCTAssertEqual(ExerciseDefaults.fallbackStartWeight(equipment: .cable, weightMode: .perSide, measurementType: .weight, loadMode: .none), 5)
        XCTAssertEqual(ExerciseDefaults.fallbackStartWeight(equipment: .cable, weightMode: .none, measurementType: .weight, loadMode: .none), 10)
        XCTAssertEqual(ExerciseDefaults.fallbackStartWeight(equipment: .barbell, weightMode: .both, measurementType: .weight, loadMode: .none), 20)
        XCTAssertEqual(ExerciseDefaults.fallbackStartWeight(equipment: .dumbbell, weightMode: .perSide, measurementType: .weight, loadMode: .none), 5)
        // 自重系は符号付き軸: 補助スタイルは補助側 −10、それ以外は 0（自重）。器具に依らない。
        XCTAssertEqual(ExerciseDefaults.fallbackStartWeight(equipment: .bodyweight, weightMode: .none, measurementType: .bodyweight, loadMode: .assisted), -10)
        XCTAssertEqual(ExerciseDefaults.fallbackStartWeight(equipment: .other, weightMode: .none, measurementType: .bodyweight, loadMode: .weighted), 0)
    }

    // MARK: - プリセット定義の整合

    /// 重量計測のプリセット種目は全件レビュー値を持つ（追加漏れ検出）。
    func testEveryWeightPresetHasEntry() {
        for preset in SeedData.presetExercises where preset.measurement == .weight {
            XCTAssertNotNil(ExerciseDefaults.entry(for: preset.name), "レビュー値なし: \(preset.name)")
        }
    }

    /// プリセットは 96 件・名前は一意（決定的 id は名前から作るため、同名は同 id に潰れる）。
    func testPresetCountAndUniqueNames() {
        let names = SeedData.presetExercises.map(\.name)
        XCTAssertEqual(names.count, 96)
        XCTAssertEqual(Set(names).count, names.count, "同名のプリセットがあります")
        for name in names {
            XCTAssertEqual(name, name.trimmingCharacters(in: .whitespacesAndNewlines), "前後空白: \(name)")
        }
    }

    /// ケーブル片側のプリセットはレビュー値も 1.25kg 刻み（フォールバック規則と一致）。
    func testCablePerSidePresetsUseQuarterStep() {
        let cablePerSide = SeedData.presetExercises.filter { $0.equipment == .cable && $0.weightMode == .perSide }
        XCTAssertFalse(cablePerSide.isEmpty)
        for preset in cablePerSide {
            XCTAssertEqual(ExerciseDefaults.entry(for: preset.name)?.weightStep, 1.25, preset.name)
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

    /// 片側/両側ラベルの整合（ダンベル=片側。1本を両手で持つ種目だけ区別なし）。
    func testWeightModeConsistency() {
        let twoHandSingleDumbbell: Set<String> = ["ダンベルプルオーバー", "ゴブレットスクワット", "オーバーヘッドエクステンション"]
        for preset in SeedData.presetExercises where preset.measurement == .weight {
            if preset.equipment == .dumbbell {
                let expected: WeightMode = twoHandSingleDumbbell.contains(preset.name) ? .none : .perSide
                XCTAssertEqual(preset.weightMode, expected, "ダンベルの数え方: \(preset.name)")
            }
        }
    }
}
