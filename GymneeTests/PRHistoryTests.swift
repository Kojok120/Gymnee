import XCTest
@testable import Gymnee

final class PRHistoryTests: XCTestCase {
    private let bench = UUID()
    private let pushup = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func weight(_ id: UUID, _ kg: Double, _ reps: Int) -> PRHistory.SetInput {
        .init(exerciseId: id, measurementType: .weight, loadMode: .none, weight: kg, reps: reps, durationSeconds: nil)
    }

    private func workout(_ day: Double, _ sets: [PRHistory.SetInput]) -> PRHistory.WorkoutInput {
        .init(id: UUID(), completedAt: t0.addingTimeInterval(day * 86_400), sets: sets)
    }

    func testEachImprovementCountsInTheWorkoutItHappened() {
        // 同じ種目で毎回重量を伸ばす人。保存値（上書き）では2回目以降が数えられなかった。
        let w1 = workout(0, [weight(bench, 60, 10)])
        let w2 = workout(2, [weight(bench, 62.5, 10)])
        let w3 = workout(4, [weight(bench, 62.5, 8)]) // 伸びていない回
        let result = PRHistory.replay([w3, w1, w2]) // 並び順に依存しない
        XCTAssertEqual(result.byWorkout[w1.id], 2, "初回は最大重量と推定1RMの2件")
        XCTAssertEqual(result.byWorkout[w2.id], 2)
        XCTAssertNil(result.byWorkout[w3.id])
        XCTAssertEqual(result.total, 4)
    }

    func testSameMetricImprovedTwiceInOneWorkoutCountsOnce() {
        let w = workout(0, [weight(bench, 60, 10), weight(bench, 65, 10)])
        XCTAssertEqual(PRHistory.replay([w]).byWorkout[w.id], 2, "最大重量と推定1RMをそれぞれ1件")
    }

    func testBodyweightRepsAndCardioIgnored() {
        let up = PRHistory.SetInput(exerciseId: pushup, measurementType: .bodyweight, loadMode: .none,
                                    weight: 0, reps: 12, durationSeconds: nil)
        let run = PRHistory.SetInput(exerciseId: UUID(), measurementType: .cardio, loadMode: .none,
                                     weight: 0, reps: 0, durationSeconds: 1200)
        let w1 = workout(0, [up, run])
        let w2 = workout(1, [PRHistory.SetInput(exerciseId: pushup, measurementType: .bodyweight, loadMode: .none,
                                                weight: 0, reps: 15, durationSeconds: nil)])
        let result = PRHistory.replay([w1, w2])
        XCTAssertEqual(result.byWorkout[w1.id], 1)
        XCTAssertEqual(result.byWorkout[w2.id], 1)
    }

    func testAssistImprovesWhenAssistGetsLighter() {
        let dips = UUID()
        func assisted(_ kg: Double) -> PRHistory.SetInput {
            .init(exerciseId: dips, measurementType: .bodyweight, loadMode: .assisted, weight: kg, reps: 8, durationSeconds: nil)
        }
        let w1 = workout(0, [assisted(-20)])
        let w2 = workout(1, [assisted(-15)])
        let w3 = workout(2, [assisted(-25)])
        let result = PRHistory.replay([w1, w2, w3])
        XCTAssertEqual(result.byWorkout[w2.id], 1)
        XCTAssertNil(result.byWorkout[w3.id], "補助が重くなった回は更新ではない")
    }
}
