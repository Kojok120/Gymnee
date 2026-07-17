import XCTest
@testable import Gymnee

/// 記録画面カテゴリタブの表示セット（シェルフ）ロジックのテスト。
final class ExerciseShelfTests: XCTestCase {

    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()
    private let e = UUID()

    // MARK: - defaultIds（頻度優先→定番補完）

    func testDefaultIdsPrefersFrequencyThenFillsWithStandards() {
        // 頻度2件 + 定番から1件補完で limit=3。
        XCTAssertEqual(
            ExerciseShelf.defaultIds(frequencyRanked: [a, b], standards: [c, d, e]),
            [a, b, c]
        )
    }

    func testDefaultIdsSkipsDuplicates() {
        // 定番と頻度が重複しても同じ id は1回だけ。
        XCTAssertEqual(
            ExerciseShelf.defaultIds(frequencyRanked: [a, b], standards: [b, a, c]),
            [a, b, c]
        )
    }

    func testDefaultIdsRespectsLimit() {
        XCTAssertEqual(
            ExerciseShelf.defaultIds(frequencyRanked: [a, b, c, d], standards: [e]),
            [a, b, c]
        )
    }

    func testDefaultIdsReturnsFewerWhenCandidatesShort() {
        // 候補が limit 未満ならあるだけ返す（core/glutes/other 等）。
        XCTAssertEqual(ExerciseShelf.defaultIds(frequencyRanked: [], standards: [a]), [a])
        XCTAssertEqual(ExerciseShelf.defaultIds(frequencyRanked: [], standards: []), [])
    }

    // MARK: - resolve（削除済み種目の読み時フィルタ）

    func testResolveDropsMissingIdsKeepingOrder() {
        XCTAssertEqual(ExerciseShelf.resolve(stored: [a, b, c], existing: [c, a]), [a, c])
        XCTAssertEqual(ExerciseShelf.resolve(stored: [a], existing: []), [])
    }

    // MARK: - ExerciseShelves（永続構造）

    func testAddMaterializesCurrentDefaultsOnFirstEdit() {
        // 未カスタマイズのタブに追加 → 現在の表示リスト（既定）を固定してから足す。
        var shelves = ExerciseShelves()
        shelves.add(d, to: .chest, current: [a, b, c])
        XCTAssertEqual(shelves.shelf(for: .chest), [a, b, c, d])
    }

    func testAddIsIdempotent() {
        var shelves = ExerciseShelves()
        shelves.add(a, to: .chest, current: [a, b])
        XCTAssertEqual(shelves.shelf(for: .chest), [a, b])   // 重複追加しないが実体化はされる
    }

    func testRemoveMaterializesCurrentDefaultsOnFirstEdit() {
        var shelves = ExerciseShelves()
        shelves.remove(b, from: .legs, current: [a, b, c])
        XCTAssertEqual(shelves.shelf(for: .legs), [a, c])
    }

    func testEmptyArrayIsDistinctFromNoCustomization() {
        // 全部外した（空配列）は「カスタマイズ済み」として尊重し、既定表示（nil）と区別する。
        var shelves = ExerciseShelves()
        XCTAssertNil(shelves.shelf(for: .chest))
        shelves.remove(a, from: .chest, current: [a])
        XCTAssertEqual(shelves.shelf(for: .chest), [])
    }

    func testEncodeDecodeRoundTrip() {
        var shelves = ExerciseShelves()
        shelves.add(a, to: .chest, current: [b])
        shelves.remove(c, from: .back, current: [c, d])
        let restored = ExerciseShelves.decode(from: shelves.encoded())
        XCTAssertEqual(restored, shelves)
    }

    func testDecodeFailsSafeOnCorruptJSON() {
        XCTAssertEqual(ExerciseShelves.decode(from: ""), ExerciseShelves())
        XCTAssertEqual(ExerciseShelves.decode(from: "{broken"), ExerciseShelves())
        XCTAssertEqual(ExerciseShelves.decode(from: "[1,2,3]"), ExerciseShelves())
    }

    // MARK: - standardNames の整合

    func testStandardNamesExistInPresets() {
        // 定番名は必ずプリセットに実在する（改名・削除時にここで検出する）。
        let presetNames = Set(SeedData.presetExercises.map { $0.name })
        for (group, names) in ExerciseShelf.standardNames {
            for name in names {
                XCTAssertTrue(presetNames.contains(name), "\(group) の定番「\(name)」がプリセットにありません")
            }
        }
    }

    func testStandardNamesMuscleGroupsMatchPresets() {
        // 定番の部位割当がプリセット定義と一致する（胸の定番に背中種目が紛れない）。
        let presetsByName = Dictionary(uniqueKeysWithValues: SeedData.presetExercises.map { ($0.name, $0.muscle) })
        for (group, names) in ExerciseShelf.standardNames {
            for name in names {
                XCTAssertEqual(presetsByName[name], group, "「\(name)」の部位が定番の割当（\(group)）と不一致")
            }
        }
    }

    func testAllMuscleGroupsHaveStandardEntry() {
        // 新しい部位 case を追加した時に定番の検討漏れを検出する（空配列は許容）。
        for group in MuscleGroup.allCases {
            XCTAssertNotNil(ExerciseShelf.standardNames[group], "\(group) の定番エントリがありません")
        }
    }
}
