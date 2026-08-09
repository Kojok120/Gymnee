import XCTest
@testable import Gymnee

/// 育成キャラの成長ロジックのテスト。
/// 「現実だけがエンジン」「やれば必ず前進する」「節目で激変する」の 3 点が崩れていないかを見る。
final class CharacterProgressTests: XCTestCase {

    private func session(sets: Int, volume: Double = 0, prs: Int = 0, daysAgo: Int = 0) -> CharacterProgress.SessionInput {
        CharacterProgress.SessionInput(
            completedAt: Date(timeIntervalSince1970: 1_700_000_000 - Double(daysAgo) * 86_400),
            completedSets: sets,
            volumeKg: volume,
            prCount: prs
        )
    }

    // MARK: - EXP

    func testEmptySessionEarnsNothing() {
        XCTAssertEqual(CharacterProgress.experience(for: session(sets: 0, volume: 1000)), 0)
    }

    /// 重量が 1kg も伸びなくても、行けば必ず EXP が入る（プラトーで止まらない）。
    func testGoingToGymAlwaysAdvances() {
        let light = CharacterProgress.experience(for: session(sets: 1, volume: 0))
        XCTAssertGreaterThan(light, 0)
        XCTAssertEqual(light, CharacterProgress.baseExpPerSession + CharacterProgress.expPerSet)
    }

    func testMoreSetsEarnMoreExp() {
        XCTAssertGreaterThan(
            CharacterProgress.experience(for: session(sets: 12)),
            CharacterProgress.experience(for: session(sets: 6))
        )
    }

    /// ボリューム EXP は逓減する（高重量者が独走しない）。
    func testVolumeExpHasDiminishingReturns() {
        let one = CharacterProgress.volumeExp(1_000)
        let four = CharacterProgress.volumeExp(4_000)
        XCTAssertEqual(four, one * 2, "4倍のボリュームで EXP は 2 倍（平方根）")
    }

    func testVolumeExpIsCappedAndSafe() {
        XCTAssertEqual(CharacterProgress.volumeExp(10_000_000), CharacterProgress.volumeExpCap)
        XCTAssertEqual(CharacterProgress.volumeExp(.nan), 0, "壊れた値は 0 に倒す（Int 変換のトラップを避ける）")
        XCTAssertEqual(CharacterProgress.volumeExp(.infinity), 0)
        XCTAssertEqual(CharacterProgress.volumeExp(-100), 0)
    }

    func testPRIsWorthABigBonus() {
        let withPR = CharacterProgress.experience(for: session(sets: 5, prs: 1))
        let without = CharacterProgress.experience(for: session(sets: 5, prs: 0))
        XCTAssertEqual(withPR - without, CharacterProgress.expPerPR)
    }

    func testTotalExperienceSumsSessions() {
        let sessions = [session(sets: 5, volume: 1000), session(sets: 8, volume: 2000, prs: 1)]
        XCTAssertEqual(
            CharacterProgress.totalExperience(sessions: sessions),
            sessions.reduce(0) { $0 + CharacterProgress.experience(for: $1) }
        )
    }

    // MARK: - レベル

    func testLevelStartsAtOne() {
        let level = CharacterProgress.level(totalExperience: 0)
        XCTAssertEqual(level.value, 1)
        XCTAssertEqual(level.expIntoLevel, 0)
        XCTAssertEqual(level.progress, 0, accuracy: 0.0001)
    }

    func testLevelUpConsumesRequiredExp() {
        let need = CharacterProgress.expForLevel(1)
        let level = CharacterProgress.level(totalExperience: need)
        XCTAssertEqual(level.value, 2)
        XCTAssertEqual(level.expIntoLevel, 0)
    }

    func testLevelProgressIsFraction() {
        let need = CharacterProgress.expForLevel(1)
        let level = CharacterProgress.level(totalExperience: need / 2)
        XCTAssertEqual(level.value, 1)
        XCTAssertEqual(level.progress, 0.5, accuracy: 0.01)
    }

    func testLevelIsMonotonicAndBounded() {
        var previous = 0
        for exp in stride(from: 0, through: 200_000, by: 5_000) {
            let value = CharacterProgress.level(totalExperience: exp).value
            XCTAssertGreaterThanOrEqual(value, previous)
            XCTAssertLessThanOrEqual(value, CharacterProgress.maxLevel)
            previous = value
        }
    }

    func testNegativeExperienceIsTreatedAsZero() {
        XCTAssertEqual(CharacterProgress.level(totalExperience: -999).value, 1)
    }

    // MARK: - 進化段階

    func testStageStartsAtRookie() {
        XCTAssertEqual(CharacterProgress.stage(level: 1, prCount: 0, weeklyStreakWeeks: 0), .rookie)
    }

    /// 3 条件すべてを満たして初めて進化する（レベルだけ高くても上がらない）。
    func testStageRequiresAllConditions() {
        XCTAssertEqual(CharacterProgress.stage(level: 40, prCount: 0, weeklyStreakWeeks: 0), .rookie)
        XCTAssertEqual(CharacterProgress.stage(level: 5, prCount: 1, weeklyStreakWeeks: 1), .trainee)
        XCTAssertEqual(CharacterProgress.stage(level: 12, prCount: 5, weeklyStreakWeeks: 3), .challenger)
    }

    func testStageNeverRegressesWithMoreProgress() {
        let mid = CharacterProgress.stage(level: 25, prCount: 15, weeklyStreakWeeks: 8)
        let more = CharacterProgress.stage(level: 30, prCount: 20, weeklyStreakWeeks: 10)
        XCTAssertGreaterThanOrEqual(more, mid)
    }

    func testNextStageListsUnmetConditions() {
        let next = CharacterProgress.nextStage(level: 5, prCount: 0, weeklyStreakWeeks: 0)
        XCTAssertEqual(next?.stage, .trainee)
        XCTAssertEqual(next?.unmet.count, 2, "レベルは満たしているので PR と連続週の 2 件だけ残る")
    }

    func testNextStageIsNilAtTop() {
        XCTAssertNil(CharacterProgress.nextStage(level: 200, prCount: 999, weeklyStreakWeeks: 999))
    }

    // MARK: - ステータス

    func testStatValueIsZeroWithoutVolume() {
        XCTAssertEqual(CharacterProgress.statValue(volumeKg: 0), 0)
        XCTAssertEqual(CharacterProgress.statValue(volumeKg: .nan), 0)
    }

    func testStatValueGrowsAndSaturates() {
        XCTAssertLessThan(CharacterProgress.statValue(volumeKg: 1_000), CharacterProgress.statValue(volumeKg: 100_000))
        XCTAssertLessThanOrEqual(CharacterProgress.statValue(volumeKg: 1_000_000_000), 99)
    }

    func testStatsCoverAllAxesAndFoldMuscleGroups() {
        let stats = CharacterProgress.stats(volumeByMuscle: [.chest: 5_000, .shoulders: 5_000, .cardio: 99_999])
        XCTAssertEqual(stats.count, CharacterProgress.Axis.allCases.count)
        XCTAssertEqual(stats[.push], CharacterProgress.statValue(volumeKg: 10_000), "胸と肩は押す力に合算される")
        XCTAssertEqual(stats[.pull], 0, "有酸素はどの軸にも寄与しない")
    }
}
