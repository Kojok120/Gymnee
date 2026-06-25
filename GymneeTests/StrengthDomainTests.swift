import XCTest
@testable import Gymnee

/// %1RM 提案（§6.5 深掘り）のテスト。
final class StrengthSuggesterTests: XCTestCase {
    func testWorkingWeightInverseEpley() {
        // e1RM120, 5reps → 120/1.1667=102.857 → 2.5丸めで102.5
        XCTAssertEqual(StrengthSuggester.workingWeight(e1RM: 120, reps: 5), 102.5, accuracy: 0.001)
    }
    func testSingleRep() {
        XCTAssertEqual(StrengthSuggester.workingWeight(e1RM: 120, reps: 1), 120, accuracy: 0.001)
    }
    func testInvalid() {
        XCTAssertEqual(StrengthSuggester.workingWeight(e1RM: 0, reps: 5), 0)
    }
    func testPercentOfMax() {
        XCTAssertEqual(StrengthSuggester.percentOfMax(weight: 100, e1RM: 120), 0.8333, accuracy: 0.001)
        XCTAssertEqual(StrengthSuggester.percentOfMax(weight: 100, e1RM: 0), 0)
    }
    func testSuggestions() {
        let s = StrengthSuggester.suggestions(e1RM: 100, reps: [1, 5])
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].weight, 100, accuracy: 0.001)
        XCTAssertLessThan(s[1].weight, 100)
    }
}
