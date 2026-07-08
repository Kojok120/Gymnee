import XCTest
@testable import Gymnee

/// プリセット種目の決定的id（UUID v5）の検証。
/// v5 が RFC 4122 準拠であることを既知ベクタで確認する＝Postgres の uuid_generate_v5 と一致する保証。
final class DeterministicIDTests: XCTestCase {
    /// RFC 4122 既知ベクタ: uuid5(NAMESPACE_DNS, "python.org") = 886313e1-3b8a-5372-9b90-0c9aee199e5d
    func testUUIDv5MatchesRFC4122Vector() {
        let dns = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        let got = UUID(v5Name: "python.org", namespace: dns)
        XCTAssertEqual(got, UUID(uuidString: "886313e1-3b8a-5372-9b90-0c9aee199e5d")!)
    }

    /// 決定的: 同じ入力なら常に同一id。
    func testPresetIdIsStable() {
        XCTAssertEqual(SeedData.presetId("ディップス"), SeedData.presetId("ディップス"))
        XCTAssertNotEqual(SeedData.presetId("ディップス"), SeedData.presetId("ベンチプレス"))
    }

    /// プリセット名→id の一覧を出力する（サーバ移行 SQL との照合・確認用）。
    func testEmitPresetMapping() {
        for p in SeedData.presetExercises {
            print("PRESET_ID\t\(p.name)\t\(SeedData.presetId(p.name).uuidString.lowercased())")
        }
    }
}
