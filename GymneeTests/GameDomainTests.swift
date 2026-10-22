import XCTest
@testable import Gymnee

/// issue #155（ゲームに振り切る）の純粋ロジック: 技・記録画面の戦闘・冒険マップ・称号。
final class TechniqueTests: XCTestCase {

    func testEveryPresetExerciseHasItsOwnTechnique() {
        let presets = SeedData.presetExercises.map(\.name)
        XCTAssertEqual(presets.count, 96)
        for name in presets {
            XCTAssertNotNil(Technique.presetNames[name], "\(name) に技名が無い")
        }
        let names = presets.map(Technique.name(exerciseName:))
        XCTAssertEqual(Set(names).count, names.count, "技名が重複している")
    }

    func testCustomExerciseBecomesSecretTechnique() {
        XCTAssertEqual(Technique.name(exerciseName: "ペックデックフライ"), "秘技・ペックデックフライ")
        XCTAssertEqual(Technique.name(exerciseName: "ベンチプレス"), "鋼鉄プレス")
    }

    func testLevelsFollowCumulativeSets() {
        XCTAssertEqual(Technique.level(sets: 0), 0)
        XCTAssertEqual(Technique.level(sets: 1), 1)
        XCTAssertEqual(Technique.level(sets: 9), 1)
        XCTAssertEqual(Technique.level(sets: 10), 2)
        XCTAssertEqual(Technique.level(sets: 10_000), Technique.maxLevel)
        XCTAssertEqual(Technique.setsToNextLevel(sets: 3), 7)
        XCTAssertNil(Technique.setsToNextLevel(sets: 10_000))
    }

    func testPowerGrowsWithLevelAndPersonalRecords() {
        XCTAssertEqual(Technique.power(level: 0, prCount: 5), 0, "覚えていない技に威力は無い")
        XCTAssertLessThan(Technique.power(level: 1, prCount: 0), Technique.power(level: 2, prCount: 0))
        XCTAssertLessThan(Technique.power(level: 2, prCount: 0), Technique.power(level: 2, prCount: 1))
    }

    func testEventOnEachSet() {
        XCTAssertEqual(Technique.event(exerciseName: "スクワット", setsBefore: 0), .learned(name: "大地の踏みこみ"))
        XCTAssertEqual(Technique.event(exerciseName: "スクワット", setsBefore: 9), .leveledUp(name: "大地の踏みこみ", level: 2))
        XCTAssertEqual(Technique.event(exerciseName: "スクワット", setsBefore: 10), .used(name: "大地の踏みこみ", level: 2))
    }

    func testBookListsPresetsAndLearnedCustomOnly() {
        let presets: [(name: String, muscle: MuscleGroup)] = [("ベンチプレス", .chest), ("スクワット", .legs)]
        let book = Technique.book(tallies: [
            Technique.Tally(exerciseName: "スクワット", muscle: .legs, completedSets: 12, prCount: 1),
            Technique.Tally(exerciseName: "スクワット", muscle: .legs, completedSets: 3),
            Technique.Tally(exerciseName: "自作プレス", muscle: .chest, completedSets: 2),
            Technique.Tally(exerciseName: "未実施の自作", muscle: .back, completedSets: 0),
        ], presets: presets)
        XCTAssertEqual(book.map(\.exerciseName), ["自作プレス", "ベンチプレス", "スクワット"],
                       "部位の順、同じ部位は覚えたものが先")
        XCTAssertEqual(book.first { $0.exerciseName == "スクワット" }?.sets, 15, "同じ種目は足し合わせる")
        XCTAssertFalse(book.first { $0.exerciseName == "ベンチプレス" }!.isLearned)
        XCTAssertEqual(book.first { $0.exerciseName == "自作プレス" }?.techniqueName, "秘技・自作プレス")
        XCTAssertEqual(Technique.learnedCount(book), 2)
    }
}

final class RecordBattleTests: XCTestCase {
    private func status(defeated: Bool = false, hp: Int = 6, damage: Int = 2) -> PartyBoss.Status {
        PartyBoss.Status(partyId: UUID(), name: nil, weekStart: Date(timeIntervalSince1970: 0), bossId: "couch_golem",
                         hp: hp, damage: damage, defeated: defeated, claimed: false, members: [])
    }

    func testFirstEverWorkoutIsTheTutorial() {
        XCTAssertEqual(RecordBattle.opponent(completedWorkouts: 0, tutorialDone: false, status: status(), weekHits: 0, weeklyGoal: 3),
                       .tutorial)
        // 宝箱を開けたあとは（記録を消して 0 回に戻っても）チュートリアルを繰り返さない。
        XCTAssertNotEqual(RecordBattle.opponent(completedWorkouts: 0, tutorialDone: true, status: nil, weekHits: 0, weeklyGoal: 3),
                          .tutorial)
    }

    func testFightsTheWeeklyBossOnlyWhileTodayCountsAsDamage() {
        let fighting = RecordBattle.opponent(completedWorkouts: 5, tutorialDone: true, status: status(), weekHits: 3, weeklyGoal: 3)
        XCTAssertEqual(fighting, .boss(bossId: "couch_golem", tier: .medium, remainingHP: 4, totalHP: 6), "目標 + 1 回目まではダメージになる")
        XCTAssertEqual(RecordBattle.opponent(completedWorkouts: 5, tutorialDone: true, status: status(), weekHits: 4, weeklyGoal: 3),
                       .dummy(.capped))
        XCTAssertEqual(RecordBattle.opponent(completedWorkouts: 5, tutorialDone: true, status: status(defeated: true),
                                             weekHits: 1, weeklyGoal: 3), .dummy(.defeated))
        XCTAssertEqual(RecordBattle.opponent(completedWorkouts: 5, tutorialDone: true, status: nil, weekHits: 1, weeklyGoal: 3),
                       .dummy(.noParty))
    }

    func testExpectedSetsPrefersThePlan() {
        XCTAssertEqual(RecordBattle.expectedSets(plannedSets: 9, recentSetCounts: [20, 20]), 9)
        XCTAssertEqual(RecordBattle.expectedSets(plannedSets: nil, recentSetCounts: [10, 30, 14]), 14, "中央値")
        XCTAssertEqual(RecordBattle.expectedSets(plannedSets: nil, recentSetCounts: []), 12)
        XCTAssertEqual(RecordBattle.expectedSets(plannedSets: 100, recentSetCounts: []), 30, "多すぎる計画は 30 で止める")
        XCTAssertEqual(RecordBattle.chipProgress(sets: 6, expectedSets: 12), 0.5)
        XCTAssertEqual(RecordBattle.chipProgress(sets: 20, expectedSets: 12), 1)
    }

    func testStrikeLabelShowsWhatWasLifted() {
        XCTAssertEqual(RecordBattle.strikeLabel(weight: 60, reps: 10, duration: nil), "600")
        XCTAssertEqual(RecordBattle.strikeLabel(weight: 0, reps: 12, duration: nil), "12回")
        XCTAssertEqual(RecordBattle.strikeLabel(weight: 0, reps: 0, duration: 45), "45秒")
        XCTAssertEqual(RecordBattle.strikeLabel(weight: .infinity, reps: 3, duration: nil), "3回")
    }

    func testLinesForStrikesAndFinish() {
        XCTAssertEqual(RecordBattle.strikeLine(event: .used(name: "鋼鉄プレス", level: 2), isPR: false), "鋼鉄プレス！")
        XCTAssertEqual(RecordBattle.strikeLine(event: .learned(name: "鋼鉄プレス"), isPR: true), "会心の一撃！ 鋼鉄プレスを おぼえた！")
        XCTAssertEqual(RecordBattle.finishLine(opponent: .boss(bossId: "couch_golem", tier: .weak, remainingHP: 1, totalHP: 3)),
                       "とどめの一撃！ ソファゴーレムを たおした！")
        XCTAssertEqual(RecordBattle.finishLine(opponent: .boss(bossId: "couch_golem", tier: .weak, remainingHP: 3, totalHP: 3)),
                       "とどめの一撃！ ソファゴーレムに 1ダメージ！")
    }
}

final class AdventureMapTests: XCTestCase {

    func testPositionWalksThroughRegionsAndLaps() {
        XCTAssertEqual(AdventureMap.stepsPerLap, 70)
        let start = AdventureMap.position(completedWorkouts: 0)
        XCTAssertEqual(start.region.name, "朝の丘")
        XCTAssertEqual(start.step, 0)
        let forest = AdventureMap.position(completedWorkouts: 10)
        XCTAssertEqual(forest.region.name, "鉄の森", "10 回で朝の丘を抜ける")
        XCTAssertEqual(forest.step, 0)
        let second = AdventureMap.position(completedWorkouts: 71)
        XCTAssertEqual(second.lap, 2)
        XCTAssertEqual(second.region.name, "朝の丘")
        XCTAssertEqual(second.step, 1)
    }

    func testNodesHaveMidBossesAndARegionBoss() {
        XCTAssertEqual(AdventureMap.node(regionIndex: 0, step: 3), .path)
        if case .midBoss = AdventureMap.node(regionIndex: 0, step: 5) {} else { XCTFail("5 マス目は中ボス") }
        XCTAssertEqual(AdventureMap.node(regionIndex: 0, step: 10), .regionBoss(bossId: "sloth_slime"))
        let next = AdventureMap.nextEncounter(from: AdventureMap.position(completedWorkouts: 2))
        XCTAssertEqual(next.remaining, 3)
    }

    func testEventsAndClearedRegions() {
        XCTAssertEqual(AdventureMap.event(completedBefore: 0), .advanced)
        if case .defeatedMidBoss = AdventureMap.event(completedBefore: 4) {} else { XCTFail("5 回目で中ボス") }
        XCTAssertEqual(AdventureMap.event(completedBefore: 9), .clearedRegion(region: "朝の丘", next: "鉄の森"))
        XCTAssertEqual(AdventureMap.event(completedBefore: 69), .clearedRegion(region: "頂", next: "朝の丘"))
        XCTAssertEqual(AdventureMap.clearedRegions(completedWorkouts: 9), 0)
        XCTAssertEqual(AdventureMap.clearedRegions(completedWorkouts: 25), 2)
        XCTAssertEqual(AdventureMap.clearedRegions(completedWorkouts: 140), 8)
    }
}

final class PlayerTitleTests: XCTestCase {

    func testIdsAreUniqueAndStable() {
        let ids = PlayerTitle.catalog.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { $0.count <= 32 }, "見た目の JSON は文字列を 32 文字で切る")
    }

    func testEarnedTitlesFollowStats() {
        var stats = PlayerTitle.Stats()
        XCTAssertTrue(PlayerTitle.earned(stats: stats).isEmpty)
        stats.workouts = 1
        stats.workoutsByMuscle = [.legs: 5, .glutes: 20]
        stats.seasonalDefeats = [.halloween]
        let earned = Set(PlayerTitle.earned(stats: stats).map(\.id))
        XCTAssertEqual(earned, ["first-step", "legs", "halloween"])
    }

    func testResolveDropsTitlesThatAreNotEarned() {
        var stats = PlayerTitle.Stats()
        XCTAssertNil(PlayerTitle.resolve(selectedId: "veteran", stats: stats))
        stats.workouts = 100
        XCTAssertEqual(PlayerTitle.resolve(selectedId: "veteran", stats: stats)?.name, "百戦錬磨")
        XCTAssertNil(PlayerTitle.resolve(selectedId: "unknown", stats: stats))
    }

    func testDisplayNameIgnoresUnknownIds() {
        XCTAssertEqual(PlayerTitle.displayName(forId: "dawn"), "夜明けの戦士")
        XCTAssertNil(PlayerTitle.displayName(forId: "from-a-newer-app"))
        XCTAssertNil(PlayerTitle.displayName(forId: nil))
    }

    func testEarlyAndLateHours() {
        XCTAssertTrue(PlayerTitle.isEarly(hour: 5))
        XCTAssertFalse(PlayerTitle.isEarly(hour: 8))
        XCTAssertTrue(PlayerTitle.isLate(hour: 22))
        XCTAssertFalse(PlayerTitle.isLate(hour: 20))
    }
}

/// 見た目の送受信に称号を足したこと・投稿に焼き込む称号・ウィジェットの判定（issue #155）。
final class GameSharingTests: XCTestCase {

    func testMemberLookCarriesTitleAndOldLooksHaveNone() {
        let look = PartyBoss.MemberLook(
            build: CharacterBuild(girth: .normal, arm: .thick, leg: .thin), skinId: "classic", stage: .trainee,
            hairStyleId: "short", accessoryId: "none", equipped: [:], title: "dawn"
        )
        let parsed = PartyBoss.MemberLook(json: look.json)
        XCTAssertEqual(parsed?.title, "dawn")
        XCTAssertNotEqual(look.fingerprint, PartyBoss.MemberLook(json: { var j = look.json; j["title"] = nil; return j }())?.fingerprint,
                          "称号を変えたら送り直す")
        // 古いアプリが送った見た目（キーが無い）は称号なし。
        var old = look.json
        old.removeValue(forKey: "title")
        XCTAssertNil(PartyBoss.MemberLook(json: old)?.title)
        // 長すぎる値は切る（他人が書いた値）。
        var long = look.json
        long["title"] = String(repeating: "a", count: 100)
        XCTAssertEqual(PartyBoss.MemberLook(json: long)?.title?.count, 32)
    }

    func testPostStatsOmitTitleWhenNone() throws {
        var stats = FeedItemStats(exercises: 1, sets: 3, volume: 1000, minutes: 30, prCount: 0, muscles: ["chest"])
        let plain = try XCTUnwrap(stats.encodedJSON())
        XCTAssertFalse(plain.contains("title"), "称号が無い投稿の JSON は今までと同じ（作り直しで差分を出さない）")
        stats.title = "legs"
        XCTAssertEqual(FeedItemStats.decode(stats.encodedJSON())?.title, "legs")
        XCTAssertNil(FeedItemStats.decode(plain)?.title)
    }

    func testWidgetCharacterSleepsAfterThreeDays() {
        let calendar = Calendar(identifier: .gregorian)
        let now = ISO8601DateFormatter().date(from: "2026-10-22T12:00:00+09:00")!
        XCTAssertTrue(WidgetArtwork.isSleeping(lastWorkoutDate: nil, now: now, calendar: calendar))
        XCTAssertFalse(WidgetArtwork.isSleeping(lastWorkoutDate: now.addingTimeInterval(-2 * 86_400), now: now, calendar: calendar))
        XCTAssertTrue(WidgetArtwork.isSleeping(lastWorkoutDate: now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar))
    }

    func testWidgetBossIsShownOnlyDuringItsWeek() {
        let start = ISO8601DateFormatter().date(from: "2026-10-19T00:00:00+09:00")!
        let boss = WidgetArtwork.Boss(name: "ソファゴーレム", remainingHP: 3, totalHP: 6, defeated: false, weekStart: start)
        XCTAssertTrue(WidgetArtwork.isCurrent(boss, now: start.addingTimeInterval(3 * 86_400)))
        XCTAssertFalse(WidgetArtwork.isCurrent(boss, now: start.addingTimeInterval(7 * 86_400)), "翌週の月曜からは出さない")
        XCTAssertFalse(WidgetArtwork.isCurrent(boss, now: start.addingTimeInterval(-1)))
    }

    func testTutorialBonusOnlyAfterOpeningTheChest() {
        XCTAssertEqual(RecordBattle.tutorialBonus(opened: false), 0)
        XCTAssertEqual(RecordBattle.tutorialBonus(opened: true), RecordBattle.tutorialChestEnergy)
        XCTAssertEqual(RecordBattle.tutorialChestEnergy, Expedition.courses[0].energyCost, "最初の遠征にちょうど出られる")
    }
}
