import XCTest
@testable import Gymnee

/// 1 回のトレーニングが育成に与えた変化。
/// **記録が育成にどう効くのか分からない**という声への答えなので、
/// 「何が起きたか」を取り違えないことがそのまま価値になる。
final class WorkoutGrowthTests: XCTestCase {

    private func gain(
        exp: Int = 164,
        energy: Int = 38,
        levelBefore: Int = 3,
        levelAfter: Int = 3,
        stageBefore: CharacterProgress.Stage = .rookie,
        stageAfter: CharacterProgress.Stage = .rookie,
        muscles: [WorkoutGrowth.MuscleShare] = [],
        prCount: Int = 0
    ) -> WorkoutGrowth.Gain {
        WorkoutGrowth.Gain(
            exp: exp,
            energy: energy,
            levelBefore: CharacterProgress.Level(value: levelBefore, expIntoLevel: 10, expForNextLevel: 320),
            levelAfter: CharacterProgress.Level(value: levelAfter, expIntoLevel: 174, expForNextLevel: 320),
            stageBefore: stageBefore,
            stageAfter: stageAfter,
            muscles: muscles,
            prCount: prCount
        )
    }

    // MARK: - 何が起きたかの判定

    func testDetectsLevelUp() {
        XCTAssertFalse(gain(levelBefore: 3, levelAfter: 3).didLevelUp)
        XCTAssertTrue(gain(levelBefore: 3, levelAfter: 4).didLevelUp)
    }

    func testDetectsEvolution() {
        XCTAssertFalse(gain(stageBefore: .rookie, stageAfter: .rookie).didEvolve)
        XCTAssertTrue(gain(stageBefore: .rookie, stageAfter: .trainee).didEvolve)
    }

    // MARK: - 見出し（起きたことのうち一番大きいものだけを言う）

    func testHeadlinePrefersEvolutionOverLevelUp() {
        let evolved = gain(levelBefore: 4, levelAfter: 5, stageBefore: .rookie, stageAfter: .trainee, prCount: 1)
        XCTAssertEqual(WorkoutGrowth.headline(for: evolved), "トレーニー になった！")
    }

    func testHeadlinePrefersLevelUpOverPR() {
        let leveled = gain(levelBefore: 3, levelAfter: 4, prCount: 2)
        XCTAssertEqual(WorkoutGrowth.headline(for: leveled), "レベルが上がった！")
    }

    func testHeadlineMentionsPRWhenNothingBigger() {
        XCTAssertEqual(WorkoutGrowth.headline(for: gain(prCount: 1)), "自己ベスト更新、お見事！")
    }

    /// 何も節目が無い日でも必ずねぎらう。**行っただけで前進している**ことを伝える回。
    func testHeadlineStillCelebratesAPlainSession() {
        XCTAssertEqual(WorkoutGrowth.headline(for: gain()), "頑張ったね！")
    }

    /// 同じ結果なら同じ言葉（乱数を使わない）。
    func testCopyIsDeterministic() {
        let g = gain(prCount: 1)
        XCTAssertEqual(WorkoutGrowth.headline(for: g), WorkoutGrowth.headline(for: g))
        XCTAssertEqual(WorkoutGrowth.detail(for: g), WorkoutGrowth.detail(for: g))
    }

    // MARK: - 説明文（この 1 回の数字で説明する）

    func testDetailStatesTheExpAndEnergy() {
        let text = WorkoutGrowth.detail(for: gain(exp: 164, energy: 38))
        XCTAssertTrue(text.contains("164"), text)
        XCTAssertTrue(text.contains("38"), text)
    }

    /// パワーが増えていない回に「0 貯まった」と書かない。
    func testDetailOmitsEnergyWhenNoneGained() {
        let text = WorkoutGrowth.detail(for: gain(energy: 0))
        XCTAssertFalse(text.contains("パワー"), text)
    }

    // MARK: - 効いた部位

    func testMusclesAreSortedByVolume() {
        let shares = WorkoutGrowth.muscleShares(volumeByMuscle: [.chest: 1200, .back: 3000, .legs: 800])
        XCTAssertEqual(shares.map(\.muscle), [.back, .chest, .legs])
    }

    func testMusclesDropZeroVolume() {
        let shares = WorkoutGrowth.muscleShares(volumeByMuscle: [.chest: 0, .back: 500])
        XCTAssertEqual(shares.map(\.muscle), [.back])
    }

    /// 量が同じでも並びが毎回入れ替わらない（同じ結果なら同じ見え方）。
    func testMuscleOrderIsStableOnTies() {
        let input: [MuscleGroup: Double] = [.chest: 1000, .back: 1000, .legs: 1000]
        let first = WorkoutGrowth.muscleShares(volumeByMuscle: input).map(\.muscle)
        for _ in 0..<10 {
            XCTAssertEqual(WorkoutGrowth.muscleShares(volumeByMuscle: input).map(\.muscle), first)
        }
    }

    func testMuscleSummaryListsAtMostThree() {
        let g = gain(muscles: [
            .init(muscle: .back, volumeKg: 3000),
            .init(muscle: .chest, volumeKg: 1200),
            .init(muscle: .legs, volumeKg: 800),
            .init(muscle: .arms, volumeKg: 400),
        ])
        let text = WorkoutGrowth.muscleSummary(for: g)
        XCTAssertEqual(text, "効いたところ: 背中・胸・脚")
    }

    func testMuscleSummaryIsNilWithoutMuscles() {
        XCTAssertNil(WorkoutGrowth.muscleSummary(for: gain(muscles: [])))
    }

    // MARK: - 次の段階

    func testNextStageHintListsWhatIsMissing() {
        let next = CharacterProgress.NextStage(stage: .trainee, unmet: ["Lv.5まであと2", "自己ベストあと1"])
        let text = WorkoutGrowth.nextStageHint(next)
        XCTAssertEqual(text, "次は トレーニー：Lv.5まであと2 / 自己ベストあと1")
    }

    func testNextStageHintWhenAlreadyQualified() {
        let next = CharacterProgress.NextStage(stage: .trainee, unmet: [])
        XCTAssertEqual(WorkoutGrowth.nextStageHint(next), "トレーニー の条件を満たしている")
    }

    /// 最上位まで行っていれば出さない。
    func testNextStageHintIsNilAtTheTop() {
        XCTAssertNil(WorkoutGrowth.nextStageHint(nil))
    }

    // MARK: - 受け渡しの鍵

    /// 保存キーは記録タブと育成タブで共有する。変えると祝いが出なくなる。
    func testPendingKeyIsFrozen() {
        XCTAssertEqual(WorkoutGrowth.Pending.key, "gymnee.character.pendingCelebration")
    }
}
