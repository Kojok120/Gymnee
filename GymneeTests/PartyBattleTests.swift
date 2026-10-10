import XCTest
@testable import Gymnee

/// 週ボスの戦闘（issue #137）。ダメージの規則は scripts/sqltest/boss_battle_test.sql と同じシナリオで突き合わせる。
final class PartyBattleTests: XCTestCase {
    private func jst(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func uid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    private let weekStart = ISO8601DateFormatter().date(from: "2026-09-28T00:00:00+09:00")!  // 月曜

    // MARK: - ジョブ（party_member_job）

    func testJobNeedsStrictMajority() {
        XCTAssertEqual(PartyBoss.Job.decide(from: [.upper, .upper, .upper]), .warrior)
        XCTAssertEqual(PartyBoss.Job.decide(from: [.lower, .lower, .upper]), .monk)
        XCTAssertEqual(PartyBoss.Job.decide(from: [.cardio, .cardio, .core, .core]), .hero, "半分ちょうどは勇者")
        XCTAssertEqual(PartyBoss.Job.decide(from: []), .hero, "記録が無ければ勇者")
        XCTAssertEqual(PartyBoss.Job.decide(from: [.cardio]), .thief)
        XCTAssertEqual(PartyBoss.Job.decide(from: [.core, .core, .upper]), .priest)
        XCTAssertEqual(PartyBoss.Job.decide(from: [.full, .full, .upper]), .hero, "全身が最多なら勇者")
    }

    // MARK: - ダメージ（party_attacks）

    /// SQL の 3. パーティ P と同じ。A（戦士・目標2）・B（武闘家・目標2）・C（勇者・目標3）。
    private func partyP() -> (raw: [PartyBoss.RawAttack], fighters: [PartyBoss.Fighter], bMonday: UUID) {
        let bMonday = UUID()
        func raw(_ n: Int, _ at: String, _ c: PartyBoss.Category, id: UUID = UUID()) -> PartyBoss.RawAttack {
            PartyBoss.RawAttack(workoutId: id, userId: uid(n), completedAt: jst(at), category: c)
        }
        return ([
            raw(1, "2026-09-28T08:00:00+09:00", .upper),
            raw(2, "2026-09-28T20:00:00+09:00", .lower, id: bMonday),
            raw(2, "2026-09-29T07:00:00+09:00", .lower),
            raw(3, "2026-09-30T12:00:00+09:00", .cardio),
            raw(1, "2026-10-03T10:00:00+09:00", .upper),
            raw(1, "2026-10-04T10:00:00+09:00", .upper),
            raw(1, "2026-10-04T11:00:00+09:00", .upper),
            raw(9, "2026-10-01T11:00:00+09:00", .upper),  // メンバーでない人は数えない
        ], [
            PartyBoss.Fighter(id: uid(1), weeklyGoal: 2, job: .warrior),
            PartyBoss.Fighter(id: uid(2), weeklyGoal: 2, job: .monk),
            PartyBoss.Fighter(id: uid(3), weeklyGoal: 3, job: .hero),
        ], bMonday)
    }

    func testScoreMatchesServerScenario() {
        let (raw, fighters, _) = partyP()
        let attacks = PartyBoss.score(raw.shuffled(), fighters: fighters)
        XCTAssertEqual(attacks.count, 7)
        XCTAssertEqual(attacks.map(\.day), ["2026-09-28", "2026-09-28", "2026-09-29", "2026-09-30",
                                            "2026-10-03", "2026-10-04", "2026-10-04"])
        XCTAssertEqual(attacks.map(\.base), [1, 1, 1, 1, 1, 1, 0], "A の4回目は上限超え")
        XCTAssertEqual(attacks.map(\.combo), [0, 1, 0, 0, 0, 0, 0], "月曜に2人目の B が連携")
        XCTAssertEqual(attacks.map(\.skill), [0, 0, 1, 0, 1, 0, 0], "B 火の連撃・A 土の底力")
        XCTAssertEqual(attacks.reduce(0) { $0 + $1.total }, 9)
    }

    func testScoreWithoutAWorkoutDropsItsComboAndSkill() {
        // SQL: party_damage(p, ws, b_mon) = 6
        let (raw, fighters, bMonday) = partyP()
        let attacks = PartyBoss.score(raw.filter { $0.workoutId != bMonday }, fighters: fighters)
        XCTAssertEqual(attacks.reduce(0) { $0 + $1.total }, 6)
    }

    func testThiefPriestAndHeroSkills() {
        // SQL の 4. パーティ Q: E（盗賊・目標1）・F（僧侶・目標1）
        let q = PartyBoss.score([
            .init(workoutId: UUID(), userId: uid(5), completedAt: jst("2026-09-29T09:00:00+09:00"), category: .cardio),
            .init(workoutId: UUID(), userId: uid(5), completedAt: jst("2026-10-01T09:00:00+09:00"), category: .cardio),
            .init(workoutId: UUID(), userId: uid(6), completedAt: jst("2026-10-01T18:00:00+09:00"), category: .core),
        ], fighters: [
            .init(id: uid(5), weeklyGoal: 1, job: .thief),
            .init(id: uid(6), weeklyGoal: 1, job: .priest),
        ])
        XCTAssertEqual(q.map(\.skill), [1, 0, 1])
        XCTAssertEqual(q.map(\.combo), [0, 0, 1])
        XCTAssertEqual(q.reduce(0) { $0 + $1.total }, 6)

        // SQL の 5. ソロの R: D（勇者・目標2）は2回目で勇気
        let r = PartyBoss.score([
            .init(workoutId: UUID(), userId: uid(4), completedAt: jst("2026-09-28T09:00:00+09:00"), category: .full),
            .init(workoutId: UUID(), userId: uid(4), completedAt: jst("2026-09-28T19:00:00+09:00"), category: .full),
        ], fighters: [.init(id: uid(4), weeklyGoal: 2, job: .hero)])
        XCTAssertEqual(r.map(\.skill), [0, 1])
        XCTAssertEqual(r.reduce(0) { $0 + $1.total }, 3)
    }

    func testDayBoundaryIsJST() {
        // 日曜 23:30 JST と 月曜 0:30 JST は別の日（連撃が成立する）。UTC ではどちらも日曜。
        let attacks = PartyBoss.score([
            .init(workoutId: UUID(), userId: uid(1), completedAt: jst("2026-10-04T23:30:00+09:00"), category: .lower),
            .init(workoutId: UUID(), userId: uid(1), completedAt: jst("2026-10-05T00:30:00+09:00"), category: .lower),
        ], fighters: [.init(id: uid(1), weeklyGoal: 3, job: .monk)])
        XCTAssertEqual(attacks.map(\.day), ["2026-10-04", "2026-10-05"])
        XCTAssertEqual(attacks.map(\.skill), [0, 1])
    }

    func testAttackIdIsMD5OfLowercasedUUID() {
        // python3 -c "import hashlib;print(hashlib.md5(b'3f2504e0-4f89-41d3-9a0c-0305e82c3301').hexdigest())"
        let id = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
        XCTAssertEqual(PartyBoss.attackId(workoutId: id), "648b604eab495b675996ff417fe1539d")
    }

    // MARK: - 応答の読み取り

    func testParsesBattleFieldsFromServerJSON() throws {
        let json = """
        {"party_id": "43938a10-512a-473f-94d2-b8c4a43a934b", "week_start": "2026-09-27T15:00:00+00:00",
         "boss_id": "snooze_dragon", "hp": 7, "damage": 9, "defeated": true, "claimed": false,
         "attacks": [
           {"id": "3ec1", "user_id": "00000000-0000-0000-0000-000000000001", "day": "2026-09-28", "category": "upper", "base": 1, "skill": 0, "combo": 0},
           {"id": "fbc7", "user_id": "00000000-0000-0000-0000-000000000002", "day": "2026-09-28", "category": "lower", "base": 1, "skill": 0, "combo": 1},
           {"id": "bad"}
         ],
         "members": [
           {"user_id": "00000000-0000-0000-0000-000000000001", "display_name": "U1", "weekly_goal": 2, "hits": 1,
            "job": "warrior", "look": {"v": 1, "girth": 9, "skin": "sunset", "stage": 2, "gear": {"head": "crown", "hand": 3}},
            "live_session_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"},
           {"user_id": "00000000-0000-0000-0000-000000000002", "display_name": "U2", "weekly_goal": 2, "hits": 1,
            "job": "ninja", "look": null, "live_session_id": null}
         ]}
        """
        let status = try XCTUnwrap(PartyBoss.status(fromJSON: try JSONSerialization.jsonObject(with: Data(json.utf8))))
        XCTAssertEqual(status.attacks.count, 2, "読めない攻撃は落とす")
        XCTAssertEqual(status.comboCount, 1)
        XCTAssertEqual(status.attacks[1].category, .lower)
        XCTAssertEqual(status.members[0].job, .warrior)
        XCTAssertEqual(status.members[1].job, .hero, "知らないジョブは勇者")
        XCTAssertNotNil(status.members[0].liveSessionId)
        XCTAssertNil(status.members[1].look)
        let look = try XCTUnwrap(status.members[0].look)
        XCTAssertEqual(look.girth, 2, "範囲外は丸める")
        XCTAssertEqual(look.skinId, "sunset")
        XCTAssertEqual(look.stageValue, .challenger)
        XCTAssertEqual(look.equippedItems[.head]?.id, "crown")
        XCTAssertNil(look.equippedItems[.hand], "文字列でない装備は捨てる")
    }

    func testOldServerWithoutBattleFieldsStillParses() throws {
        let json = """
        {"party_id": "43938a10-512a-473f-94d2-b8c4a43a934b", "week_start": "2026-10-05T00:00:00+09:00",
         "boss_id": "junk_kraken", "hp": 5, "damage": 2, "defeated": false, "claimed": false,
         "members": [{"user_id": "00000000-0000-0000-0000-000000000001", "display_name": "U1", "weekly_goal": 3, "hits": 2}]}
        """
        let status = try XCTUnwrap(PartyBoss.status(fromJSON: try JSONSerialization.jsonObject(with: Data(json.utf8))))
        XCTAssertTrue(status.attacks.isEmpty)
        XCTAssertEqual(status.members[0].job, .hero)
        XCTAssertNil(status.members[0].look)
    }

    // MARK: - 見た目

    func testLookRoundTripsAndRejectsGarbage() throws {
        let look = PartyBoss.MemberLook(
            build: CharacterBuild(girth: .normal, arm: .thick, leg: .thin), skinId: "midnight", stage: .veteran,
            hairStyleId: "long", accessoryId: "glasses",
            equipped: [.head: Expedition.item(id: "cap")!, .aura: Expedition.item(id: "legend-aura")!]
        )
        let data = try JSONSerialization.data(withJSONObject: look.json)
        let decoded = try XCTUnwrap(PartyBoss.MemberLook(json: try JSONSerialization.jsonObject(with: data)))
        XCTAssertEqual(decoded, look)
        XCTAssertEqual(decoded.fingerprint, look.fingerprint)
        XCTAssertEqual(decoded.build, CharacterBuild(girth: .normal, arm: .thick, leg: .thin))
        XCTAssertNil(PartyBoss.MemberLook(json: [1, 2]))
        XCTAssertNil(PartyBoss.MemberLook(json: nil))
        // 部位の合わない装備は着けない。長すぎる id は切る。
        let odd = try XCTUnwrap(PartyBoss.MemberLook(json: ["gear": ["head": "golden-grip"], "skin": String(repeating: "x", count: 100)]))
        XCTAssertTrue(odd.equippedItems.isEmpty)
        XCTAssertEqual(odd.skinId.count, 32)
    }

    /// 性別（issue #141）。送って読めること、キーの無い古い見た目は男性になること、指紋に入ること。
    func testLookCarriesGenderAndDefaultsToMale() throws {
        let female = PartyBoss.MemberLook(
            build: CharacterBuild(girth: .slim, arm: .thin, leg: .thin), skinId: "classic", stage: .rookie,
            hairStyleId: "bob", accessoryId: "none", equipped: [:], gender: .female
        )
        let data = try JSONSerialization.data(withJSONObject: female.json)
        let decoded = try XCTUnwrap(PartyBoss.MemberLook(json: try JSONSerialization.jsonObject(with: data)))
        XCTAssertEqual(decoded.genderValue, .female)
        XCTAssertEqual(decoded, female)

        var legacy = female.json
        legacy.removeValue(forKey: "g")
        XCTAssertEqual(try XCTUnwrap(PartyBoss.MemberLook(json: legacy)).genderValue, .male, "古いアプリの見た目は男性")
        legacy["g"] = "unknown"
        XCTAssertEqual(try XCTUnwrap(PartyBoss.MemberLook(json: legacy)).genderValue, .male, "知らない値は男性")

        var male = female
        male.gender = CharacterGender.male.rawValue
        XCTAssertNotEqual(male.fingerprint, female.fingerprint, "性別を変えても送り直されない")
    }

    func testLookJSONFitsServerLimit() throws {
        let look = PartyBoss.MemberLook(
            build: CharacterBuild(girth: .wide, arm: .thick, leg: .thick), skinId: "gymnee", stage: .legend,
            hairStyleId: "ponytail", accessoryId: "headphones",
            equipped: Dictionary(uniqueKeysWithValues: Expedition.Slot.allCases.map { slot in
                (slot, Expedition.items(in: slot).last!)
            })
        )
        // サーバーの制約は octet_length(character_look::text) <= 1024。
        XCTAssertLessThan(try JSONSerialization.data(withJSONObject: look.json).count, 1024)
    }

    // MARK: - 再生

    private func status(attacks: [PartyBoss.Attack], hp: Int, members: [PartyBoss.Member]) -> PartyBoss.Status {
        var s = PartyBoss.Status(
            partyId: UUID(), name: nil, weekStart: weekStart, bossId: "couch_golem", hp: hp,
            damage: attacks.reduce(0) { $0 + $1.total }, defeated: attacks.reduce(0) { $0 + $1.total } >= hp,
            claimed: false, members: members
        )
        s.attacks = attacks
        return s
    }

    private func fighters() -> [PartyBoss.Member] {
        var a = PartyBoss.Member(id: uid(1), displayName: "こうじ", avatarURL: nil, weeklyGoal: 2, hits: 4)
        a.job = .warrior
        var b = PartyBoss.Member(id: uid(2), displayName: "けんたろう", avatarURL: nil, weeklyGoal: 2, hits: 2)
        b.job = .monk
        let c = PartyBoss.Member(id: uid(3), displayName: "さき", avatarURL: nil, weeklyGoal: 3, hits: 1)
        return [a, b, c]
    }

    func testReplayPlaysUnseenAttacksAndEndsAtServerHP() {
        let (raw, f, _) = partyP()
        let s = status(attacks: PartyBoss.score(raw, fighters: f), hp: 7, members: fighters())
        let seen = Set(s.attacks.prefix(2).map(\.id))
        let replay = PartyBattle.replay(status: s, seen: seen, userId: uid(1))
        XCTAssertEqual(replay.steps.count, 5)
        XCTAssertEqual(replay.skipped, 0)
        // 既に見た2回（A月 1 + B月 2）を引いた 4 から始まる。
        XCTAssertEqual(replay.startHP, 4)
        XCTAssertEqual(replay.steps.map(\.hpAfter), [2, 1, 0, 0, 0])
        XCTAssertEqual(replay.steps.map(\.defeats), [false, false, true, false, false])
        XCTAssertEqual(replay.steps[0].lines.first, "けんたろうの \(PartyBoss.Category.lower.move(seed: s.attacks[2].id))！")
        XCTAssertTrue(replay.steps[0].lines.contains("武闘家の 連撃！ さらに 1"))
        XCTAssertTrue(replay.steps[2].lines.contains("ソファゴーレムを たおした！"))
        XCTAssertEqual(replay.steps[3].lines.last, "しかし ソファゴーレムは もう たおれている", "倒したあとの攻撃")
    }

    func testOverCapAttackSaysSo() {
        let (raw, f, _) = partyP()
        let s = status(attacks: PartyBoss.score(raw, fighters: f), hp: 20, members: fighters())
        let replay = PartyBattle.replay(status: s, seen: [], userId: uid(1), limit: 7)
        XCTAssertEqual(replay.steps.last?.lines.last, "しかし 今週の上限を こえていた")
    }

    func testReplayKeepsOnlyRecentAndNamesComboPartner() {
        let (raw, f, _) = partyP()
        let s = status(attacks: PartyBoss.score(raw, fighters: f), hp: 20, members: fighters())
        let replay = PartyBattle.replay(status: s, seen: [], userId: uid(1), limit: 6)
        XCTAssertEqual(replay.steps.count, 6)
        XCTAssertEqual(replay.skipped, 1)
        XCTAssertEqual(replay.startHP, 19, "まとめた A月 の 1 は先に引く")
        XCTAssertTrue(replay.steps[0].lines.contains("あなたと 連携攻撃！ さらに 1"), "\(replay.steps[0].lines)")
        XCTAssertEqual(replay.steps.last?.hpAfter, s.remainingHP)
    }

    func testNothingToReplayWhenAllSeen() {
        let (raw, f, _) = partyP()
        let s = status(attacks: PartyBoss.score(raw, fighters: f), hp: 20, members: fighters())
        let replay = PartyBattle.replay(status: s, seen: Set(s.attacks.map(\.id)), userId: uid(1))
        XCTAssertTrue(replay.steps.isEmpty)
        XCTAssertEqual(replay.startHP, s.remainingHP)
    }

    // MARK: - セリフ

    func testIdleMessages() {
        let members = fighters()
        var s = status(attacks: [], hp: 7, members: members)
        // 水曜まで誰も攻撃していない → 挑発が入る。自分のジョブとスキルも出す。
        var messages = PartyBattle.idleMessages(status: s, userId: uid(1), now: jst("2026-09-30T12:00:00+09:00"))
        XCTAssertTrue(messages.contains { $0.hasPrefix("ソファゴーレムが ふかふかの") })
        XCTAssertTrue(messages.contains { $0.contains("あなたは 戦士。底力") })
        XCTAssertTrue(messages.contains { $0.contains("連携攻撃") })
        // 月曜は静かでも挑発しない。
        messages = PartyBattle.idleMessages(status: s, userId: uid(1), now: jst("2026-09-28T12:00:00+09:00"))
        XCTAssertFalse(messages.contains { $0.contains("ふかふか") })
        // 残り1。
        s.attacks = [PartyBoss.Attack(id: "x", userId: uid(1), day: "2026-09-28", category: .upper, base: 1, skill: 0, combo: 0)]
        s = status(attacks: s.attacks, hp: 2, members: members)
        messages = PartyBattle.idleMessages(status: s, userId: uid(1), now: jst("2026-09-28T12:00:00+09:00"))
        XCTAssertEqual(messages.first, "あと 1撃で たおせる！\nトレーニング 1回で とどめだ")
        // 撃破済み。
        s = status(attacks: s.attacks, hp: 1, members: members)
        XCTAssertEqual(PartyBattle.idleMessages(status: s, userId: uid(1), now: .now), ["宝箱が おちている！\nタップして 開けよう"])
    }

    // MARK: - 完了直後の「ボスに攻撃」

    func testStrike() throws {
        let s = status(attacks: [], hp: 7, members: fighters())
        XCTAssertNil(PartyBattle.strike(statuses: [], weekHits: 1, weeklyGoal: 3), "パーティが無ければ出さない")
        let first = try XCTUnwrap(PartyBattle.strike(statuses: [s], weekHits: 1, weeklyGoal: 3))
        XCTAssertTrue(first.damaging)
        XCTAssertEqual(first.title, "ソファゴーレムに 1撃！")
        XCTAssertTrue(try XCTUnwrap(PartyBattle.strike(statuses: [s], weekHits: 4, weeklyGoal: 3)).damaging, "目標+1回目まで")
        XCTAssertFalse(try XCTUnwrap(PartyBattle.strike(statuses: [s], weekHits: 5, weeklyGoal: 3)).damaging)
        XCTAssertTrue(try XCTUnwrap(PartyBattle.strike(statuses: [s, s], weekHits: 1, weeklyGoal: 3)).detail.contains("2つのパーティ"))
    }

    func testWeekHitsCountsFromMondayJST() {
        let now = jst("2026-10-06T12:00:00+09:00")
        XCTAssertEqual(PartyBattle.weekHits(completedAt: [
            jst("2026-10-04T23:59:00+09:00"),  // 先週の日曜
            jst("2026-10-05T00:01:00+09:00"),
            jst("2026-10-06T08:00:00+09:00"),
        ], now: now), 2)
    }
}
