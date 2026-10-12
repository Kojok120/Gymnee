import XCTest
import SwiftData
@testable import Gymnee

/// 投稿に出す「投稿時点」の値（今月○日目・育成キャラのレベル）。
/// 過去の投稿が、今の記録で数え直した値に上書きされないこと（どの投稿も同じ「4日目」になっていた不具合）。
final class FeedSnapshotTests: XCTestCase {

    private let userId = UUID()
    private let cal = Calendar.current

    private func at(_ month: Int, _ day: Int, hour: Int = 7) -> Date {
        DateComponents(calendar: cal, year: 2026, month: month, day: day, hour: hour).date!
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: GymneeSchema.schema,
            configurations: ModelConfiguration(schema: GymneeSchema.schema, isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// 1 種目 1 セットの完了ワークアウト（育成の入力になるようセットを持たせる）。
    private func workout(_ date: Date, weight: Double = 60, in context: ModelContext) -> Workout {
        let workout = Workout(userId: userId, date: date, completedAt: date)
        context.insert(workout)
        let exercise = Exercise(name: "ベンチプレス", muscleGroup: .chest, equipment: .barbell)
        context.insert(exercise)
        let line = WorkoutExercise(orderIndex: 0, workout: workout, exercise: exercise)
        context.insert(line)
        context.insert(ExerciseSet(setIndex: 0, weight: weight, reps: 10, isCompleted: true, workoutExercise: line))
        return workout
    }

    func testFeedShowsEachPostsOwnMonthlyDay() throws {
        let context = try makeContext()
        let oct6 = workout(at(10, 6), in: context)
        let oct8 = workout(at(10, 8, hour: 21), in: context)
        let oct11 = workout(at(10, 11), in: context)
        try context.save()

        let entries = FeedBuilder.build(personalRecords: [], workouts: [oct6, oct8, oct11], publishedVisibilityById: [:])
        let monthlyDay = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.monthlyDay) })
        XCTAssertEqual(monthlyDay[oct6.id], 1)
        XCTAssertEqual(monthlyDay[oct8.id], 2)
        XCTAssertEqual(monthlyDay[oct11.id], 3)
    }

    func testCharacterBadgeIsCountedAsOfThePost() throws {
        let context = try makeContext()
        let workouts = (1...12).map { workout(at(9, $0), weight: 60 + Double($0) * 5, in: context) }
        try context.save()

        let first = try XCTUnwrap(CharacterInputs.badge(asOf: at(9, 1), completed: workouts, weeklyGoal: 3))
        let last = try XCTUnwrap(CharacterInputs.badge(asOf: at(9, 12), completed: workouts, weeklyGoal: 3))
        XCTAssertLessThan(first.level, last.level, "最初の投稿のレベルが今のレベルになっている")
        // 同じ時点なら、あとから記録が増えても値は変わらない。
        let firstOfFewer = try XCTUnwrap(CharacterInputs.badge(asOf: at(9, 1), completed: Array(workouts.prefix(1)), weeklyGoal: 3))
        XCTAssertEqual(first.level, firstOfFewer.level)
        XCTAssertEqual(first.stage, firstOfFewer.stage)
        XCTAssertNil(CharacterInputs.badge(asOf: at(8, 31), completed: workouts, weeklyGoal: 3), "まだ記録が無い時点")
    }
}
