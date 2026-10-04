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
