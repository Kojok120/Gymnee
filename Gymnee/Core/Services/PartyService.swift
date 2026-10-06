import Foundation
import Observation

/// 友達と倒す「週ボス」（issue #128。複数パーティは #130）の状況と操作。
///
/// **サーバーが正**。ダメージの集計・撃破・報酬の受け取りはサーバーで数えて検証する
/// （0040_party_boss.sql）。ここは読み取った状況を画面に渡すだけで、オフラインでは何もしない。
/// 例外として、受け取った報酬（パワー）は遠征に使える残高に効くので、最後に読めた分を端末に控える。
@MainActor
@Observable
final class PartyService {
    enum JoinError: Error, Equatable {
        case full
        case tooMany
        case notFound
        case failed
    }

    /// 入っている全パーティの今週の状況（入った順。issue #130）。
    private(set) var statuses: [PartyBoss.Status] = []
    /// 画面で見ているパーティ。無ければ先頭。
    var selectedPartyId: UUID?
    private(set) var rewards: [PartyBoss.Reward] = []
    private(set) var isLoading = false
    /// 最後の読み込みが失敗したか（オフライン・未サインインなど）。
    private(set) var loadFailed = false

    private var client: SupabaseClient?

    func configure(client: SupabaseClient) { self.client = client }

    /// 画面で見ているパーティの状況。
    var status: PartyBoss.Status? {
        statuses.first { $0.partyId == selectedPartyId } ?? statuses.first
    }

    /// どれかのパーティで、倒したのに宝箱を開けていない（育成タブのボタンの印）。
    var hasUnclaimedChest: Bool { statuses.contains(where: \.hasUnclaimedChest) }

    var canCreateParty: Bool { statuses.count < PartyBoss.maxPartiesPerUser }

    /// 受け取った報酬のパワー合計（遠征の残高に上乗せする）。
    var rewardEnergy: Int { PartyBoss.totalEnergy(from: rewards) }
    /// 受け取った報酬の EXP 合計（キャラの成長に上乗せする。issue #133）。
    var rewardExp: Int { PartyBoss.totalExp(from: rewards) }

    /// 状況を取り直す。`createIfNeeded` はボス画面を開いたとき（1つも無ければ1人パーティを作る）だけ true。
    /// 育成タブのバッジのために読むだけのときは、パーティを勝手に作らない。
    func refresh(userId: UUID, weeklyGoal: Int, createIfNeeded: Bool) async {
        guard let client, await client.isAuthenticated else {
            loadFailed = true
            return
        }
        restoreRewards(userId: userId)
        isLoading = true
        defer { isLoading = false }
        do {
            if createIfNeeded {
                _ = try await client.ensureMyParty(weeklyGoal: weeklyGoal)
            }
            statuses = PartyBoss.statuses(fromJSON: try await client.myParties())
            if let selected = selectedPartyId, !statuses.contains(where: { $0.partyId == selected }) {
                selectedPartyId = nil
            }
            let rows = try await client.bossRewards()
            rewards = rows.compactMap(PartyBoss.reward(fromJSON:))
            storeRewards(userId: userId)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// 招待されたパーティに入る。今のパーティはそのまま。入ったパーティを表示に切り替える。
    func join(_ partyId: UUID, userId: UUID, weeklyGoal: Int) async -> Result<Void, JoinError> {
        guard let client, await client.isAuthenticated else { return .failure(.failed) }
        do {
            try await client.joinParty(partyId, weeklyGoal: weeklyGoal)
        } catch {
            return .failure(Self.joinError(error))
        }
        selectedPartyId = partyId
        await refresh(userId: userId, weeklyGoal: weeklyGoal, createIfNeeded: false)
        return .success(())
    }

    /// 新しいパーティを作る（別のグループ用）。作ったパーティを表示に切り替える。
    func create(name: String?, userId: UUID, weeklyGoal: Int) async -> Result<Void, JoinError> {
        guard let client, await client.isAuthenticated else { return .failure(.failed) }
        let created: UUID?
        do {
            created = try await client.createParty(weeklyGoal: weeklyGoal, name: name)
        } catch {
            return .failure(Self.joinError(error))
        }
        selectedPartyId = created
        await refresh(userId: userId, weeklyGoal: weeklyGoal, createIfNeeded: false)
        return .success(())
    }

    /// 指定したパーティを抜ける。最後の1つを抜けたら1人パーティからやり直す。
    func leave(_ partyId: UUID, userId: UUID, weeklyGoal: Int) async {
        guard let client, await client.isAuthenticated else { return }
        try? await client.leaveParty(partyId)
        if selectedPartyId == partyId { selectedPartyId = nil }
        await refresh(userId: userId, weeklyGoal: weeklyGoal, createIfNeeded: true)
    }

    /// パーティの名前を変える。nil で未設定（メンバー名で表示）に戻す。
    func rename(_ partyId: UUID, name: String?, userId: UUID, weeklyGoal: Int) async {
        guard let client, await client.isAuthenticated else { return }
        try? await client.renameParty(partyId, name: name)
        await refresh(userId: userId, weeklyGoal: weeklyGoal, createIfNeeded: false)
    }

    /// 宝箱を開ける。開けた報酬を返す（撃破していない・通信失敗なら nil）。
    func claim(_ partyId: UUID, userId: UUID, weeklyGoal: Int) async -> PartyBoss.Reward? {
        guard let client, let target = statuses.first(where: { $0.partyId == partyId }), target.defeated,
              await client.isAuthenticated
        else { return nil }
        guard let reward = PartyBoss.reward(fromJSON: try? await client.claimBossReward(partyId: partyId, weekStart: target.weekStart))
        else { return nil }
        await refresh(userId: userId, weeklyGoal: weeklyGoal, createIfNeeded: false)
        return reward
    }

    /// 翌週のボスのランクに投票する（日曜 23:59 JST まで変えられる）。
    func vote(_ tier: PartyBoss.Tier, partyId: UUID, userId: UUID, weeklyGoal: Int) async {
        guard let client, await client.isAuthenticated else { return }
        try? await client.voteBossTier(partyId: partyId, tier: tier.rawValue)
        await refresh(userId: userId, weeklyGoal: weeklyGoal, createIfNeeded: false)
    }

    // MARK: - 戦闘画面（issue #137）

    /// 自分のキャラの見た目を載せる。前回送った見た目と同じなら送らない（部屋を開くたびに呼ばれる）。
    func publishLook(_ look: PartyBoss.MemberLook, userId: UUID) async {
        guard !isDemo, let client, await client.isAuthenticated else { return }
        let key = "gymnee.party.look.\(userId.uuidString.lowercased())"
        guard UserDefaults.standard.string(forKey: key) != look.fingerprint else { return }
        do {
            try await client.setCharacterLook(look.json)
            UserDefaults.standard.set(look.fingerprint, forKey: key)
        } catch {
            // 次に部屋を開いたときに送り直す。
        }
    }

    /// 戦闘画面で再生し終えた攻撃（パーティごと、今週の分だけ）。次に開いたときは新しい攻撃だけを再生する。
    func seenAttackIds(partyId: UUID, weekStart: Date) -> Set<String> {
        if isDemo { return demoSeen[partyId] ?? [] }
        guard let row = UserDefaults.standard.dictionary(forKey: seenKey(partyId)),
              (row["week"] as? Double) == weekStart.timeIntervalSince1970
        else { return [] }
        return Set(row["ids"] as? [String] ?? [])
    }

    func markSeen(_ ids: [String], partyId: UUID, weekStart: Date) {
        guard !ids.isEmpty else { return }
        let merged = seenAttackIds(partyId: partyId, weekStart: weekStart).union(ids)
        if isDemo {
            demoSeen[partyId] = merged
            return
        }
        // 週が替わったら前の週の分は捨てる（1パーティの1週は最大 5人 × 数回なので小さい）。
        UserDefaults.standard.set(["week": weekStart.timeIntervalSince1970, "ids": Array(merged)], forKey: seenKey(partyId))
    }

    private func seenKey(_ partyId: UUID) -> String { "gymnee.party.seen.\(partyId.uuidString.lowercased())" }

    /// デモ（DEBUG の画面確認）中か。端末に何も残さない。
    private var isDemo = false
    private var demoSeen: [UUID: Set<String>] = [:]

    /// 設定で週目標を変えたとき、全パーティの HP に反映する（入っていなければ何もしない）。
    func syncWeeklyGoal(_ weeklyGoal: Int) async {
        guard let client, await client.isAuthenticated else { return }
        try? await client.setPartyWeeklyGoal(weeklyGoal)
    }

    private static func joinError(_ error: Error) -> JoinError {
        guard case let SupabaseClient.SupabaseError.http(_, body) = error else { return .failed }
        if body.contains("party is full") { return .full }
        if body.contains("too many parties") { return .tooMany }
        if body.contains("party not found") { return .notFound }
        return .failed
    }

    #if DEBUG
    /// 画面確認用のデモ状態（`-gymneeScreen boss` / `boss-defeated`）。サーバー無しで描画を確かめる。
    /// 攻撃の内訳はサーバーと同じ規則（`PartyBoss.score`）で組み立てる。
    func loadDemo(userId: UUID, defeated: Bool, solo: Bool = false) {
        isDemo = true
        demoSeen = [:]
        let weekStart = PartyBoss.weekStart(for: .now)
        let kenta = UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!
        let saki = UUID(uuidString: "00000000-0000-0000-0000-0000000000a2")!
        let haruka = UUID(uuidString: "00000000-0000-0000-0000-0000000000a3")!
        func at(_ day: Int, _ hour: Int) -> Date {
            weekStart.addingTimeInterval(TimeInterval(day * 86_400 + hour * 3_600))
        }
        func attack(_ user: UUID, _ date: Date, _ category: PartyBoss.Category) -> PartyBoss.RawAttack {
            PartyBoss.RawAttack(workoutId: UUID(), userId: user, completedAt: date, category: category)
        }
        func party(_ name: String?, _ members: [PartyBoss.Member], raw: [PartyBoss.RawAttack],
                   tier: PartyBoss.Tier = .medium) -> PartyBoss.Status {
            let hp = tier.hp(goals: members.map(\.weeklyGoal))
            let attacks = PartyBoss.score(raw, fighters: members.map {
                PartyBoss.Fighter(id: $0.id, weeklyGoal: $0.weeklyGoal, job: $0.job)
            })
            let damage = attacks.reduce(0) { $0 + $1.total }
            var status = PartyBoss.Status(
                partyId: UUID(), name: name, weekStart: weekStart, bossId: PartyBoss.bossId(forWeekStart: weekStart),
                hp: hp, damage: damage, defeated: damage >= hp, claimed: false, members: members
            )
            status.tier = tier
            status.rewardExp = tier.rewardExp
            status.nextVotes = [.weak: 0, .medium: 1, .strong: 1]
            status.myNextVote = .strong
            status.attacks = attacks
            return status
        }
        func member(_ id: UUID, _ name: String, goal: Int, hits: Int, job: PartyBoss.Job,
                    look: PartyBoss.MemberLook? = nil, live: Bool = false) -> PartyBoss.Member {
            var m = PartyBoss.Member(id: id, displayName: name, avatarURL: nil, weeklyGoal: goal, hits: hits)
            m.job = job
            m.look = look
            m.liveSessionId = live ? UUID() : nil
            return m
        }
        let kentaLook = PartyBoss.MemberLook(
            build: CharacterBuild(girth: .wide, arm: .thick, leg: .thin), skinId: "sunset", stage: .challenger,
            hairStyleId: "short", accessoryId: "none",
            equipped: [.head: Expedition.item(id: "sweat-band")!, .waist: Expedition.item(id: "lifting-belt")!]
        )
        let sakiLook = PartyBoss.MemberLook(
            build: CharacterBuild(girth: .slim, arm: .thin, leg: .thick), skinId: "midnight", stage: .trainee,
            hairStyleId: "ponytail", accessoryId: "none", equipped: [.aura: Expedition.item(id: "sweat-aura")!]
        )
        var gymRaw = [
            attack(userId, at(0, 7), .upper),
            attack(kenta, at(0, 20), .lower),
            attack(saki, at(1, 6), .cardio),
        ]
        if defeated {
            gymRaw += [attack(kenta, at(1, 19), .lower), attack(userId, at(1, 21), .upper), attack(saki, at(1, 22), .cardio)]
        }
        statuses = [
            party("ジム仲間", [
                member(userId, "こうじ", goal: 3, hits: defeated ? 2 : 1, job: .warrior),
                member(kenta, "けんたろう", goal: 2, hits: defeated ? 2 : 1, job: .monk, look: kentaLook, live: !defeated),
                member(saki, "さき", goal: 2, hits: defeated ? 2 : 1, job: .thief, look: sakiLook),
            ], raw: gymRaw, tier: defeated ? .weak : .medium),
            party(nil, [
                member(userId, "こうじ", goal: 3, hits: 1, job: .warrior),
                member(haruka, "はるか", goal: 2, hits: 2, job: .priest),
            ], raw: [attack(userId, at(0, 7), .upper), attack(haruka, at(0, 12), .core), attack(haruka, at(1, 12), .core)]),
        ]
        if solo {
            statuses = [party(nil, [member(userId, "こうじ", goal: 3, hits: 1, job: .warrior)],
                              raw: [attack(userId, at(0, 7), .upper)])]
        }
        selectedPartyId = statuses.first?.partyId
        rewards = [
            PartyBoss.Reward(weekStart: weekStart.addingTimeInterval(-604_800), bossId: "snooze_dragon", energy: 60, tier: .strong, exp: 400),
            PartyBoss.Reward(weekStart: weekStart.addingTimeInterval(-3 * 604_800), bossId: "sloth_slime", energy: 60),
            PartyBoss.Reward(weekStart: weekStart.addingTimeInterval(-7 * 604_800), bossId: "sloth_slime", energy: 60),
        ]
    }
    #endif

    // MARK: - 報酬の控え（オフラインでも遠征の残高を崩さない）

    private func rewardsKey(_ userId: UUID) -> String { "gymnee.party.rewards.\(userId.uuidString.lowercased())" }

    /// 端末の控えを読む。サーバーから読めた後は上書きされる。
    func restoreRewards(userId: UUID) {
        guard rewards.isEmpty,
              let rows = UserDefaults.standard.array(forKey: rewardsKey(userId)) as? [[String: Any]]
        else { return }
        rewards = rows.compactMap { row in
            guard let ts = row["week_start"] as? Double, let bossId = row["boss_id"] as? String else { return nil }
            return PartyBoss.Reward(weekStart: Date(timeIntervalSince1970: ts), bossId: bossId,
                                    energy: row["energy"] as? Int ?? 0,
                                    tier: (row["tier"] as? String).flatMap(PartyBoss.Tier.init(rawValue:)) ?? .medium,
                                    exp: row["exp"] as? Int ?? 0)
        }
    }

    private func storeRewards(userId: UUID) {
        let rows: [[String: Any]] = rewards.map {
            ["week_start": $0.weekStart.timeIntervalSince1970, "boss_id": $0.bossId, "energy": $0.energy,
             "tier": $0.tier.rawValue, "exp": $0.exp]
        }
        UserDefaults.standard.set(rows, forKey: rewardsKey(userId))
    }
}
