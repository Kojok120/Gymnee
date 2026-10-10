import XCTest
@testable import Gymnee

final class PartyBossTests: XCTestCase {
    private func jst(_ text: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: text)!
    }

    // MARK: - サーバー（0040_party_boss.sql）と同じ規則か

    func testWeekStartsMondayMidnightJST() {
        // scripts/sqltest/party_boss_test.sql の期待値と同じ。
        XCTAssertEqual(PartyBoss.weekStart(for: jst("2026-10-05T00:30:00+09:00")), jst("2026-10-05T00:00:00+09:00"))
        XCTAssertEqual(PartyBoss.weekStart(for: jst("2026-10-04T23:30:00+09:00")), jst("2026-09-28T00:00:00+09:00"))
        // UTC では日曜でも、JST で月曜なら新しい週。
        XCTAssertEqual(PartyBoss.weekStart(for: jst("2026-10-04T15:30:00Z")), jst("2026-10-05T00:00:00+09:00"))
    }

    func testBossRotationMatchesServer() {
        XCTAssertEqual(PartyBoss.bossId(forWeekStart: jst("2026-01-05T00:00:00+09:00")), "sloth_slime")
        XCTAssertEqual(PartyBoss.bossId(forWeekStart: jst("2026-01-12T00:00:00+09:00")), "couch_golem")
        XCTAssertEqual(PartyBoss.bossId(forWeekStart: jst("2025-12-29T00:00:00+09:00")), "junk_kraken")
        XCTAssertEqual(PartyBoss.bossId(forWeekStart: jst("2026-10-05T00:00:00+09:00")), "junk_kraken")
    }

    func testDamageCappedAtGoalPlusOne() {
        XCTAssertEqual(PartyBoss.cappedDamage(hits: 5, weeklyGoal: 3), 4)
        XCTAssertEqual(PartyBoss.cappedDamage(hits: 2, weeklyGoal: 3), 2)
        XCTAssertEqual(PartyBoss.cappedDamage(hits: -1, weeklyGoal: 3), 0)
    }

    func testDaysLeft() {
        let monday = jst("2026-10-05T00:00:00+09:00")
        XCTAssertEqual(PartyBoss.daysLeft(in: monday, now: jst("2026-10-05T09:00:00+09:00")), 7)
        XCTAssertEqual(PartyBoss.daysLeft(in: monday, now: jst("2026-10-11T23:00:00+09:00")), 1)
    }

    // MARK: - 応答の読み取り

    func testParsesPartyStatusFromServerJSON() throws {
        // サーバーの TimeZone が UTC のときの実際の応答（ローカル検証で取得した形）。
        let json = """
        {"party_id" : "43938a10-512a-473f-94d2-b8c4a43a934b", "week_start" : "2026-10-04T15:00:00+00:00",
         "boss_id" : "junk_kraken", "hp" : 5, "damage" : 5, "defeated" : true, "claimed" : false,
         "members" : [{"user_id" : "00000000-0000-0000-0000-000000000001", "display_name" : "U1", "avatar_url" : null, "weekly_goal" : 3, "hits" : 6},
                      {"user_id" : "00000000-0000-0000-0000-000000000002", "display_name" : "", "avatar_url" : null, "weekly_goal" : 2, "hits" : 1}]}
        """
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let status = try XCTUnwrap(PartyBoss.status(fromJSON: object))
        XCTAssertEqual(status.weekStart, jst("2026-10-05T00:00:00+09:00"))
        XCTAssertEqual(status.boss?.name, "ジャンククラーケン")
        XCTAssertEqual(status.remainingHP, 0)
        XCTAssertTrue(status.hasUnclaimedChest)
        XCTAssertEqual(status.members.map(\.damage), [4, 1])
        XCTAssertEqual(status.members[1].displayName, "メンバー", "空の表示名は置き換える")
        XCTAssertTrue(status.canInvite)
    }

    // MARK: - 複数パーティ（issue #130）

    private func member(_ id: UUID, _ name: String) -> PartyBoss.Member {
        .init(id: id, displayName: name, avatarURL: nil, weeklyGoal: 3, hits: 0)
    }

    private func status(name: String?, members: [PartyBoss.Member]) -> PartyBoss.Status {
        .init(partyId: UUID(), name: name, weekStart: .now, bossId: "sloth_slime", hp: 3, damage: 0,
              defeated: false, claimed: false, members: members)
    }

    func testTitleUsesNameOrOtherMembers() {
        let me = UUID()
        XCTAssertEqual(status(name: "ジム仲間", members: [member(me, "自分")]).title(for: me), "ジム仲間")
        XCTAssertEqual(status(name: nil, members: [member(me, "自分")]).title(for: me), "ソロ")
        XCTAssertEqual(status(name: nil, members: [member(me, "自分"), member(UUID(), "けん")]).title(for: me), "けんと")
        let many = [member(me, "自分"), member(UUID(), "けん"), member(UUID(), "さき"), member(UUID(), "はる")]
        XCTAssertEqual(status(name: nil, members: many).title(for: me), "けん・さき ほか1人と")
    }

    func testParsesMyPartiesArray() throws {
        let json = """
        [{"party_id":"43938a10-512a-473f-94d2-b8c4a43a934b","name":"職場","week_start":"2026-10-04T15:00:00+00:00","boss_id":"junk_kraken","hp":3,"damage":1,"defeated":false,"claimed":false,"members":[]},
         {"party_id":"broken"},
         {"party_id":"53938a10-512a-473f-94d2-b8c4a43a934b","name":null,"week_start":"2026-10-04T15:00:00+00:00","boss_id":"junk_kraken","hp":3,"damage":3,"defeated":true,"claimed":false,"members":[]}]
        """
        let statuses = PartyBoss.statuses(fromJSON: try JSONSerialization.jsonObject(with: Data(json.utf8)))
        XCTAssertEqual(statuses.count, 2, "読めない要素は落とす")
        XCTAssertEqual(statuses.first?.name, "職場")
        XCTAssertNil(statuses.last?.name)
        XCTAssertTrue(statuses.last?.hasUnclaimedChest ?? false)
        XCTAssertEqual(PartyBoss.statuses(fromJSON: NSNull()).count, 0)
    }

    func testNormalizedName() {
        XCTAssertEqual(PartyBoss.normalizedName("  ジム  "), "ジム")
        XCTAssertNil(PartyBoss.normalizedName("   "))
        XCTAssertEqual(PartyBoss.normalizedName(String(repeating: "あ", count: 30))?.count, PartyBoss.maxNameLength)
    }

    // MARK: - ランク（issue #133）

    func testTierHPMatchesServer() {
        // scripts/sqltest/party_boss_test.sql の 12 と同じ値（目標 3・2・2）。
        let goals = [3, 2, 2]
        XCTAssertEqual(PartyBoss.Tier.weak.hp(goals: goals), 5)
        XCTAssertEqual(PartyBoss.Tier.medium.hp(goals: goals), 7)
        XCTAssertEqual(PartyBoss.Tier.strong.hp(goals: goals), 10)
        XCTAssertEqual(PartyBoss.Tier.weak.hp(goals: [1]), 1, "最低1")
        XCTAssertEqual(PartyBoss.Tier.strong.hp(goals: []), 0)
        XCTAssertEqual(PartyBoss.Tier.allCases.map(\.rewardExp), [100, 200, 400])
    }

    func testParsesTierAndVotes() throws {
        let json = """
        {"party_id":"43938a10-512a-473f-94d2-b8c4a43a934b","name":null,"week_start":"2026-10-04T15:00:00+00:00",
         "boss_id":"junk_kraken","tier":"strong","reward_exp":400,"hp":10,"damage":3,"defeated":false,"claimed":false,
         "next_votes":{"weak":1,"medium":0,"strong":2},"my_next_vote":"weak","members":[]}
        """
        let status = try XCTUnwrap(PartyBoss.status(fromJSON: try JSONSerialization.jsonObject(with: Data(json.utf8))))
        XCTAssertEqual(status.tier, .strong)
        XCTAssertEqual(status.rewardExp, 400)
        XCTAssertEqual(status.nextVotes, [.weak: 1, .medium: 0, .strong: 2])
        XCTAssertEqual(status.myNextVote, .weak)
    }

    func testOldServerResponseDefaultsToMedium() throws {
        // 0042 より前のサーバー（tier を返さない）でも読める。
        let json = """
        {"party_id":"43938a10-512a-473f-94d2-b8c4a43a934b","week_start":"2026-10-04T15:00:00+00:00","boss_id":"junk_kraken",
         "hp":7,"damage":0,"defeated":false,"claimed":false,"members":[]}
        """
        let status = try XCTUnwrap(PartyBoss.status(fromJSON: try JSONSerialization.jsonObject(with: Data(json.utf8))))
        XCTAssertEqual(status.tier, .medium)
        XCTAssertNil(status.myNextVote)
        XCTAssertEqual(status.nextVotes[.strong], 0)
    }

    func testRewardExpAndVoteDeadline() {
        let week = jst("2026-10-05T00:00:00+09:00")
        let rewards = [
            PartyBoss.Reward(weekStart: week, bossId: "junk_kraken", energy: 60, tier: .strong, exp: 400),
            PartyBoss.Reward(weekStart: week, bossId: "sloth_slime", energy: 60),
        ]
        XCTAssertEqual(PartyBoss.totalExp(from: rewards), 400, "0042 より前の報酬は EXP 0")
        XCTAssertEqual(PartyBoss.voteDeadline(forWeekStart: week), jst("2026-10-11T23:59:59+09:00"))
    }

    func testStrongSpriteHasCrownAndSameWidth() {
        for boss in PartyBoss.catalog {
            let strong = PixelBossArt.sprite(bossId: boss.id, tier: .strong)
            let base = PixelBossArt.sprite(bossId: boss.id, tier: .medium)
            XCTAssertEqual(strong.width, base.width)
            XCTAssertGreaterThan(strong.height, base.height - 4, "王冠の分だけ背が高い（空き行は詰める）")
        }
    }

    func testNoPartyOrBrokenJSONIsNil() {
        XCTAssertNil(PartyBoss.status(fromJSON: NSNull()))
        XCTAssertNil(PartyBoss.status(fromJSON: ["party_id": "x"]))
    }

    func testTrophiesAndEnergyFromRewards() {
        let rewards = [
            PartyBoss.Reward(weekStart: jst("2026-09-28T00:00:00+09:00"), bossId: "snooze_dragon", energy: 60),
            PartyBoss.Reward(weekStart: jst("2026-10-05T00:00:00+09:00"), bossId: "snooze_dragon", energy: 60),
            PartyBoss.Reward(weekStart: jst("2026-09-21T00:00:00+09:00"), bossId: "couch_golem", energy: 60),
        ]
        let trophies = PartyBoss.trophies(from: rewards)
        XCTAssertEqual(trophies.map(\.boss.id), PartyBoss.catalog.map(\.id), "図鑑は catalog の順")
        XCTAssertEqual(trophies.map(\.defeats), [0, 1, 2, 0])
        XCTAssertEqual(PartyBoss.totalEnergy(from: rewards), 180)
    }

    func testParsesTimestampVariants() {
        let expected = jst("2026-10-05T00:00:00+09:00")
        XCTAssertEqual(PartyBoss.parseTimestamp("2026-10-04T15:00:00+00:00"), expected)
        XCTAssertEqual(PartyBoss.parseTimestamp("2026-10-04T15:00:00+00"), expected)
        XCTAssertEqual(PartyBoss.parseTimestamp("2026-10-04T15:00:00.000Z"), expected)
    }

    // MARK: - 育成タブの入口（issue #139）

    private func entryStatus(boss: String = "snooze_dragon", hp: Int = 20, damage: Int, claimed: Bool = false,
                             tier: PartyBoss.Tier = .medium) -> PartyBoss.Status {
        var s = PartyBoss.Status(
            partyId: UUID(), name: nil, weekStart: jst("2026-10-05T00:00:00+09:00"), bossId: boss,
            hp: hp, damage: damage, defeated: damage >= hp, claimed: claimed, members: []
        )
        s.tier = tier
        return s
    }

    func testEntryWithoutPartyUsesThisWeeksBoss() {
        let entry = PartyBoss.entry(statuses: [], selected: nil, now: jst("2026-10-07T12:00:00+09:00"))
        XCTAssertEqual(entry.bossId, "junk_kraken", "パーティが無くても週のボスを出す")
        XCTAssertEqual(entry.detail, "ジャンククラーケン")
        XCTAssertEqual(entry.title, "ボスに挑む")
        XCTAssertNil(entry.gauge)
        XCTAssertFalse(entry.hasChest)
    }

    func testEntryShowsRemainingHPWhileFighting() {
        let fighting = entryStatus(hp: 20, damage: 5, tier: .strong)
        let entry = PartyBoss.entry(statuses: [fighting], selected: fighting, now: .now)
        XCTAssertEqual(entry.title, "ボスに挑む")
        XCTAssertEqual(entry.detail, "ネボウドラゴン")
        XCTAssertEqual(entry.tier, .strong)
        XCTAssertEqual(entry.gauge, PartyBoss.Entry.Gauge(remaining: 15, total: 20))
        XCTAssertEqual(entry.gauge?.ratio ?? 0, 0.75, accuracy: 0.0001)
    }

    func testEntryPrefersUnclaimedChestOfAnyParty() {
        // 見ているパーティは戦闘中でも、別のパーティの宝箱を先に知らせる。
        let fighting = entryStatus(damage: 5)
        let chest = entryStatus(hp: 10, damage: 12, tier: .weak)
        let entry = PartyBoss.entry(statuses: [fighting, chest], selected: fighting, now: .now)
        XCTAssertEqual(entry.title, "宝箱を開ける")
        XCTAssertEqual(entry.detail, "ネボウドラゴンを倒した！")
        XCTAssertEqual(entry.tier, .weak, "絵は宝箱のあるパーティのランク")
        XCTAssertNil(entry.gauge)
        XCTAssertTrue(entry.hasChest)
    }

    func testEntryAfterClaimedDefeat() {
        let done = entryStatus(hp: 10, damage: 10, claimed: true)
        let entry = PartyBoss.entry(statuses: [done], selected: done, now: .now)
        XCTAssertEqual(entry.title, "今週は撃破済み")
        XCTAssertNil(entry.gauge)
        XCTAssertFalse(entry.hasChest)
    }

    func testEntryGaugeRatioWithZeroHP() {
        XCTAssertEqual(PartyBoss.Entry.Gauge(remaining: 0, total: 0).ratio, 0, "HP 0 で割らない")
    }

    // MARK: - 招待リンク

    func testPartyInviteLinkRoundTripAndAppScheme() {
        let id = UUID(uuidString: "43938A10-512A-473F-94D2-B8C4A43A934B")!
        let url = PartyInviteLink.url(for: id)
        XCTAssertEqual(url.absoluteString, "https://gymnee.app/party/?p=43938a10-512a-473f-94d2-b8c4a43a934b")
        XCTAssertEqual(PartyInviteLink.partyId(from: url), id)
        XCTAssertEqual(PartyInviteLink.partyId(from: URL(string: "gymnee://party?p=\(id.uuidString)")!), id)
        // フレンド招待とは混ざらない。
        XCTAssertNil(PartyInviteLink.partyId(from: URL(string: "https://gymnee.app/invite/?u=\(id.uuidString)")!))
        XCTAssertNil(InviteLink.userId(from: url))
        XCTAssertNil(PartyInviteLink.partyId(from: URL(string: "gymnee://auth-callback?p=\(id.uuidString)")!))
    }
}
