import XCTest
@testable import Gymnee

/// キャラのひとこと。**行動につながる用事ほど先に出す**という優先順位が要件そのものなので、
/// 優先順位が入れ替わっていないかを固定する。
final class CharacterChatterTests: XCTestCase {

    func testAwaitingClaimWinsOverEverything() {
        // 記録も済んでいない・元気も余っている状況でも、受け取り待ちが最優先。
        let context = CharacterChatter.Context(
            recordedToday: false,
            weeklyDone: 0,
            weeklyGoal: 3,
            energy: 500,
            cheapestCourseCost: 20,
            expedition: .awaitingClaim,
            partners: ["ゆうき"]
        )
        XCTAssertEqual(CharacterChatter.line(for: context).action, .claim)
    }

    func testUnrecordedTodayPromptsWorkout() {
        let context = CharacterChatter.Context(recordedToday: false, weeklyDone: 1, weeklyGoal: 3)
        let line = CharacterChatter.line(for: context)
        XCTAssertEqual(line.action, .startWorkout)
        XCTAssertTrue(line.text.contains("2回"), "残り回数が伝わっていない: \(line.text)")
    }

    func testLastOneRemainingIsCalledOut() {
        let context = CharacterChatter.Context(recordedToday: false, weeklyDone: 2, weeklyGoal: 3)
        XCTAssertTrue(CharacterChatter.line(for: context).text.contains("あと1回"))
    }

    /// 週の目標を達成済みでも、今日まだなら記録へ促す（達成後に無言にならない）。
    func testGoalMetButNotRecordedTodayStillPrompts() {
        let context = CharacterChatter.Context(recordedToday: false, weeklyDone: 5, weeklyGoal: 3)
        XCTAssertEqual(CharacterChatter.line(for: context).action, .startWorkout)
    }

    func testExpeditionSuggestedWhenEnergyAllows() {
        let context = CharacterChatter.Context(
            recordedToday: true, energy: 60, cheapestCourseCost: 20, expedition: .idle
        )
        XCTAssertEqual(CharacterChatter.line(for: context).action, .expedition)
    }

    func testNoExpeditionSuggestionWhenEnergyIsShort() {
        let context = CharacterChatter.Context(
            recordedToday: true, energy: 5, cheapestCourseCost: 20, expedition: .idle
        )
        XCTAssertNil(CharacterChatter.line(for: context).action)
    }

    /// 出せるコースが無いとき（レベル不足）は遠征を勧めない。
    func testNoExpeditionSuggestionWhenNoCourseUnlocked() {
        let context = CharacterChatter.Context(
            recordedToday: true, energy: 9_999, cheapestCourseCost: nil, expedition: .idle
        )
        XCTAssertNil(CharacterChatter.line(for: context).action)
    }

    func testRunningExpeditionReportsRemainingTime() {
        let context = CharacterChatter.Context(
            recordedToday: true, energy: 0, expedition: .running(remaining: "あと2時間")
        )
        let line = CharacterChatter.line(for: context)
        XCTAssertTrue(line.text.contains("あと2時間"), line.text)
        XCTAssertNil(line.action)
    }

    func testNextStageHintWhenNothingElseToDo() {
        let context = CharacterChatter.Context(
            recordedToday: true, energy: 0, expedition: .idle, nextStageUnmet: ["Lv.5まであと2"]
        )
        XCTAssertTrue(CharacterChatter.line(for: context).text.contains("Lv.5まであと2"))
    }

    func testSmallTalkIsDeterministicPerSeed() {
        let context = CharacterChatter.Context(recordedToday: true, energy: 0, expedition: .idle)
        let a = CharacterChatter.line(for: context, seed: 7)
        let b = CharacterChatter.line(for: context, seed: 7)
        XCTAssertEqual(a, b)
    }

    func testEveryContextProducesNonEmptyText() {
        // どんな状態でも空のふきだしを出さない。
        let states: [CharacterChatter.ExpeditionState] = [.idle, .running(remaining: "あと1分"), .awaitingClaim]
        for recorded in [true, false] {
            for state in states {
                for energy in [0, 40, 400] {
                    let line = CharacterChatter.line(
                        for: CharacterChatter.Context(
                            recordedToday: recorded, weeklyDone: 1, weeklyGoal: 3,
                            energy: energy, cheapestCourseCost: 20, expedition: state
                        ),
                        seed: UInt64(energy)
                    )
                    XCTAssertFalse(line.text.isEmpty, "recorded=\(recorded) state=\(state) energy=\(energy)")
                }
            }
        }
    }

    // MARK: - 仲間の名前

    func testPartnerLabelFormatting() {
        XCTAssertEqual(CharacterChatter.partnerLabel([]), "")
        XCTAssertEqual(CharacterChatter.partnerLabel(["ゆうき"]), "ゆうき")
        XCTAssertEqual(CharacterChatter.partnerLabel(["ゆうき", "みか"]), "ゆうきとみか")
        XCTAssertEqual(CharacterChatter.partnerLabel(["ゆうき", "みか", "けん"]), "ゆうきたち")
    }
}
