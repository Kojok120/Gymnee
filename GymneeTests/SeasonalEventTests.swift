import XCTest
@testable import Gymnee

/// 季節のボス（issue #155）。イベントの週の判定と、サーバーのボス id の読み替え。
final class SeasonalEventTests: XCTestCase {
    private func jst(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    // MARK: - イベントの週

    func testHalloweenWeekContainsOctober31() {
        // 2026-10-31 は土曜。その週（10/26 月〜11/1 日）だけがハロウィン。
        XCTAssertEqual(SeasonalEvent.event(forWeekStart: jst("2026-10-26T00:00:00+09:00")), .halloween)
        XCTAssertNil(SeasonalEvent.event(forWeekStart: jst("2026-10-19T00:00:00+09:00")))
        XCTAssertNil(SeasonalEvent.event(forWeekStart: jst("2026-11-02T00:00:00+09:00")))
        // 2027-10-31 は日曜なので、その週の最終日。
        XCTAssertEqual(SeasonalEvent.event(forWeekStart: jst("2027-10-25T00:00:00+09:00")), .halloween)
        XCTAssertNil(SeasonalEvent.event(forWeekStart: jst("2027-11-01T00:00:00+09:00")))
    }

    func testChristmasAndNewYearDoNotOverlap() {
        XCTAssertEqual(SeasonalEvent.event(forWeekStart: jst("2026-12-21T00:00:00+09:00")), .christmas)
        // 年をまたぐ週（12/28〜1/3）は 1/1 を含むので年末年始。
        XCTAssertEqual(SeasonalEvent.event(forWeekStart: jst("2026-12-28T00:00:00+09:00")), .newYear)
        XCTAssertNil(SeasonalEvent.event(forWeekStart: jst("2027-01-04T00:00:00+09:00")))
    }

    func testEventAtUsesJapaneseWeek() {
        // UTC では 11/1 日曜 15:30 でも、JST では 11/2 月曜 0:30 ＝ もう次の週。
        XCTAssertNil(SeasonalEvent.event(at: jst("2026-11-01T15:30:00Z")))
        XCTAssertEqual(SeasonalEvent.event(at: jst("2026-11-01T14:30:00Z")), .halloween)
    }

    // MARK: - 読み替え

    func testDisplayBossIdReplacesOnlyDuringEventWeeks() {
        let halloween = jst("2026-10-26T00:00:00+09:00")
        XCTAssertEqual(SeasonalEvent.displayBossId(serverBossId: "snooze_dragon", weekStart: halloween), "pumpkin_slime")
        XCTAssertEqual(SeasonalEvent.displayBossId(serverBossId: "snooze_dragon", weekStart: jst("2026-10-19T00:00:00+09:00")),
                       "snooze_dragon")
        XCTAssertEqual(PartyBoss.displayBossId(forWeekStart: halloween), "pumpkin_slime")
        // サーバーの写しは読み替えない（テストでサーバーの値と照合しているため）。
        XCTAssertEqual(PartyBoss.bossId(forWeekStart: halloween), "snooze_dragon")
    }

    func testStatusFromServerIsShownAsSeasonalBoss() throws {
        let json = """
        {"party_id":"43938a10-512a-473f-94d2-b8c4a43a934b","week_start":"2026-10-25T15:00:00+00:00",
         "boss_id":"snooze_dragon","hp":3,"damage":1,"defeated":false,"claimed":false,"members":[]}
        """
        let status = try XCTUnwrap(PartyBoss.status(fromJSON: try JSONSerialization.jsonObject(with: Data(json.utf8))))
        XCTAssertEqual(status.bossId, "pumpkin_slime")
        XCTAssertEqual(status.boss?.name, "カボチャスライム")
        XCTAssertEqual(PartyBattle.taunt(bossId: status.bossId), SeasonalEvent.halloween.taunt)
    }

    func testRewardFromServerIsShownAsSeasonalBoss() throws {
        let reward = try XCTUnwrap(PartyBoss.reward(fromJSON: [
            "week_start": "2026-12-20T15:00:00+00:00", "boss_id": "snooze_dragon", "energy": 60, "tier": "weak", "exp": 100,
        ]))
        XCTAssertEqual(reward.bossId, "santa_golem")
    }

    // MARK: - 図鑑と限定装備

    func testTrophiesCountSeasonalDefeatsByWeek() {
        let rewards = [
            // 読み替える前の id で控えた報酬でも、週で数える。
            PartyBoss.Reward(weekStart: jst("2026-10-26T00:00:00+09:00"), bossId: "snooze_dragon", energy: 60),
            PartyBoss.Reward(weekStart: jst("2026-10-05T00:00:00+09:00"), bossId: "junk_kraken", energy: 60),
        ]
        let trophies = PartyBoss.trophies(from: rewards)
        XCTAssertEqual(trophies.count, PartyBoss.catalog.count + SeasonalEvent.allCases.count)
        XCTAssertEqual(trophies.first { $0.boss.id == "pumpkin_slime" }?.defeats, 1)
        XCTAssertEqual(trophies.first { $0.boss.id == "santa_golem" }?.defeats, 0)
        XCTAssertEqual(trophies.first { $0.boss.id == "junk_kraken" }?.defeats, 1)
    }

    func testOwnedLimitedItemsComeFromSeasonalRewards() {
        let rewards = [
            PartyBoss.Reward(weekStart: jst("2026-10-26T00:00:00+09:00"), bossId: "pumpkin_slime", energy: 60),
            PartyBoss.Reward(weekStart: jst("2026-10-05T00:00:00+09:00"), bossId: "junk_kraken", energy: 60),
        ]
        XCTAssertEqual(SeasonalEvent.ownedItemIds(rewards: rewards), ["witch-hat"])
        XCTAssertTrue(SeasonalEvent.ownedItemIds(rewards: []).isEmpty)
    }

    func testLimitedItemsAreEquippableButNeverDropFromExpeditions() {
        for event in SeasonalEvent.allCases {
            let item = event.rewardItem
            XCTAssertEqual(Expedition.item(id: item.id), item)
            XCTAssertTrue(Expedition.items(in: item.slot).contains(item))
            XCTAssertEqual(CharacterOutfit.resolve(loadout: [item.slot: item.id], owned: [item.id])[item.slot], item)
        }
        let limited = Set(Expedition.limitedItems.map(\.id))
        for _ in 0..<500 {
            for course in Expedition.courses {
                let drop = Expedition.reward(courseId: course.id, seed: UUID(), coop: true)
                XCTAssertFalse(limited.contains(drop.id), "遠征から限定装備が出た: \(drop.id)")
            }
        }
    }

    func testSeasonalBossesAreDrawnWithoutCrown() {
        for event in SeasonalEvent.allCases {
            let strong = PixelBossArt.sprite(bossId: event.boss.id, tier: .strong)
            XCTAssertEqual(strong.height, PixelBossArt.canvasHeight, "\(event.boss.id) は帽子があるので王冠を載せない")
            XCTAssertNotEqual(PixelBossArt.sprite(bossId: event.boss.id), PixelBossArt.slime, "\(event.boss.id) に専用の絵が要る")
        }
    }
}
