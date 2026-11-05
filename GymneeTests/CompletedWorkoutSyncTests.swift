import XCTest
@testable import Gymnee

/// #170: 完了済みの記録を直したときに、変更（特に削除）がサーバーへ届くこと。
final class CompletedWorkoutSyncTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let setRow = CompletedWorkoutSync.Row(id: UUID(), updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    private let weRow = CompletedWorkoutSync.Row(id: UUID(), updatedAt: Date(timeIntervalSince1970: 1_700_000_001))
    private let exRow = CompletedWorkoutSync.Row(id: UUID(), updatedAt: Date(timeIntervalSince1970: 1_700_000_002))

    private func summary(_ changes: [PendingChange]) -> [String] {
        changes.map { "\($0.entity):\($0.operation.rawValue)" }
    }

    func testDraftEditsAreNotSentUntilFinish() {
        let edits: [CompletedWorkoutSync.Edit] = [
            .added(set: setRow, workoutExercise: weRow, exercise: exRow),
            .edited(set: setRow),
            .deleted(setId: setRow.id, removedWorkoutExercise: weRow.id),
            .removedEmptyWorkoutExercise(id: weRow.id),
        ]
        for edit in edits {
            XCTAssertTrue(CompletedWorkoutSync.changes(for: edit, isCompleted: false, now: now).isEmpty, "\(edit)")
        }
    }

    func testDeletingSetOfCompletedWorkoutSendsDelete() {
        let changes = CompletedWorkoutSync.changes(
            for: .deleted(setId: setRow.id, removedWorkoutExercise: nil), isCompleted: true, now: now
        )
        XCTAssertEqual(summary(changes), ["exercise_sets:delete"])
        XCTAssertEqual(changes.first?.recordId, setRow.id)
        XCTAssertEqual(changes.first?.updatedAt, now)
    }

    func testDeletingLastSetAlsoDeletesWorkoutExercise() {
        let changes = CompletedWorkoutSync.changes(
            for: .deleted(setId: setRow.id, removedWorkoutExercise: weRow.id), isCompleted: true, now: now
        )
        XCTAssertEqual(summary(changes), ["exercise_sets:delete", "workout_exercises:delete"])
        XCTAssertEqual(changes.last?.recordId, weRow.id)
    }

    func testAddingSetSendsParentsFirst() {
        let changes = CompletedWorkoutSync.changes(
            for: .added(set: setRow, workoutExercise: weRow, exercise: exRow), isCompleted: true, now: now
        )
        XCTAssertEqual(summary(changes), ["exercises:upsert", "workout_exercises:upsert", "exercise_sets:upsert"])
        XCTAssertEqual(changes.map(\.recordId), [exRow.id, weRow.id, setRow.id])
        // 更新時刻は行の値を使う（LWW の比較に使われるため、送る時刻で上書きしない）。
        XCTAssertEqual(changes.map(\.updatedAt), [exRow.updatedAt, weRow.updatedAt, setRow.updatedAt])
    }

    func testAddingSetWithPresetExerciseDoesNotSendExercise() {
        let changes = CompletedWorkoutSync.changes(
            for: .added(set: setRow, workoutExercise: weRow, exercise: nil), isCompleted: true, now: now
        )
        XCTAssertEqual(summary(changes), ["workout_exercises:upsert", "exercise_sets:upsert"])
    }

    func testEditingSetSendsUpsert() {
        let changes = CompletedWorkoutSync.changes(for: .edited(set: setRow), isCompleted: true, now: now)
        XCTAssertEqual(summary(changes), ["exercise_sets:upsert"])
        XCTAssertEqual(changes.first?.updatedAt, setRow.updatedAt)
    }

    func testRemovingEmptyWorkoutExerciseOnRecompletionSendsDelete() {
        let changes = CompletedWorkoutSync.changes(
            for: .removedEmptyWorkoutExercise(id: weRow.id), isCompleted: true, now: now
        )
        XCTAssertEqual(summary(changes), ["workout_exercises:delete"])
    }
}
