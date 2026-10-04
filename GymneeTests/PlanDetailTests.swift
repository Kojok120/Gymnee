import XCTest
@testable import Gymnee

final class PlanDetailTests: XCTestCase {
    func testDecodesAIPlanFormatWithWeight() throws {
        let ai = [SupabaseClient.PlanExercise(name: "ベンチプレス", muscleGroup: "chest", sets: 3, reps: 8, weight: 60)]
        let json = String(data: try JSONEncoder().encode(ai), encoding: .utf8)
        XCTAssertEqual(PlanDetail.decode(json),
                       [.init(name: "ベンチプレス", muscleGroup: "chest", sets: 3, reps: 8, weight: 60)])
    }

    func testDecodesCoachFormatWithWeightKg() {
        // コーチ提案の旧形式（端末に残っている既存データ）。これが読めず計画タブが空になっていた（#121）。
        let json = #"[{"name":"スクワット","sets":3,"reps":10,"weightKg":40}]"#
        XCTAssertEqual(PlanDetail.decode(json),
                       [.init(name: "スクワット", muscleGroup: nil, sets: 3, reps: 10, weight: 40)])
    }

    func testWeightTakesPrecedenceOverWeightKg() {
        let json = #"[{"name":"a","sets":1,"reps":1,"weight":20,"weightKg":40}]"#
        XCTAssertEqual(PlanDetail.decode(json).first?.weight, 20)
    }

    func testMissingWeightIsZero() {
        XCTAssertEqual(PlanDetail.decode(#"[{"name":"腕立て伏せ","sets":3,"reps":10}]"#).first?.weight, 0)
    }

    func testFractionalCountsAreRoundedAndClamped() {
        let json = #"[{"name":"a","sets":2.6,"reps":0,"weight":9999},{"name":"b","sets":1e300,"reps":-5,"weight":-9999}]"#
        let items = PlanDetail.decode(json)
        XCTAssertEqual(items[0].sets, 3)
        XCTAssertEqual(items[0].reps, 1)
        XCTAssertEqual(items[0].weight, PlanDetail.Exercise.maxWeight)
        XCTAssertEqual(items[1].sets, 1, "巨大値は欠損扱い（トラップさせない）")
        XCTAssertEqual(items[1].reps, 1)
        XCTAssertEqual(items[1].weight, -PlanDetail.Exercise.maxWeight)
    }

    func testBrokenOrEmptyInputIsEmpty() {
        XCTAssertEqual(PlanDetail.decode(nil), [])
        XCTAssertEqual(PlanDetail.decode("{broken"), [])
        XCTAssertEqual(PlanDetail.decode(#"[{"name":"","sets":1,"reps":1}]"#), [])
    }

    func testEncodeWritesWeightKeyAndEmptyIsNil() throws {
        XCTAssertNil(PlanDetail.encode([]))
        let json = try XCTUnwrap(PlanDetail.encode([.init(name: "a", muscleGroup: nil, sets: 1, reps: 2, weight: 3)]))
        XCTAssertTrue(json.contains(#""weight":3"#))
        XCTAssertFalse(json.contains("weightKg"))
    }
}
