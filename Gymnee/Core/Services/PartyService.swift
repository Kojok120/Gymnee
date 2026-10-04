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
    func loadDemo(userId: UUID, defeated: Bool) {
        let weekStart = PartyBoss.weekStart(for: .now)
        func party(_ name: String?, _ members: [PartyBoss.Member], defeated: Bool) -> PartyBoss.Status {
            let hp = members.reduce(0) { $0 + $1.weeklyGoal }
            return PartyBoss.Status(
                partyId: UUID(), name: name, weekStart: weekStart, bossId: PartyBoss.bossId(forWeekStart: weekStart),
                hp: hp, damage: min(hp, members.reduce(0) { $0 + $1.damage }),
                defeated: defeated, claimed: false, members: members
            )
        }
        statuses = [
            party("ジム仲間", [
                PartyBoss.Member(id: userId, displayName: "こうじ", avatarURL: nil, weeklyGoal: 3, hits: defeated ? 4 : 2),
                PartyBoss.Member(id: UUID(), displayName: "けんたろう", avatarURL: nil, weeklyGoal: 2, hits: defeated ? 2 : 1),
                PartyBoss.Member(id: UUID(), displayName: "さき", avatarURL: nil, weeklyGoal: 4, hits: defeated ? 4 : 1),
            ], defeated: defeated),
            party(nil, [
                PartyBoss.Member(id: userId, displayName: "こうじ", avatarURL: nil, weeklyGoal: 3, hits: defeated ? 4 : 2),
                PartyBoss.Member(id: UUID(), displayName: "はるか", avatarURL: nil, weeklyGoal: 2, hits: 2),
            ], defeated: true),
        ]
        selectedPartyId = statuses.first?.partyId
        rewards = [
            PartyBoss.Reward(weekStart: weekStart.addingTimeInterval(-604_800), bossId: "snooze_dragon", energy: 60),
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
                                    energy: row["energy"] as? Int ?? 0)
        }
    }

    private func storeRewards(userId: UUID) {
        let rows: [[String: Any]] = rewards.map {
            ["week_start": $0.weekStart.timeIntervalSince1970, "boss_id": $0.bossId, "energy": $0.energy]
        }
        UserDefaults.standard.set(rows, forKey: rewardsKey(userId))
    }
}
