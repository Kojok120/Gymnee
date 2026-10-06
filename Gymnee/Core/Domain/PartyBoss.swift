import Foundation

/// 友達と倒す「週ボス」（issue #128）。
///
/// 正はサーバー（`supabase/migrations/0040_party_boss.sql`）。ダメージ・撃破・報酬の受け取りは
/// サーバーで数えて検証する。ここに置くのは、サーバーの返す状況を表示用に解釈する純粋関数と、
/// サーバーと同じ規則（週の境界・ボスの並び・1人あたりの上限）の写し。写しはテストでサーバーの値と照合する。
enum PartyBoss {
    struct Boss: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        /// ボスの由来（何をサボらせる敵か）。画面の説明に出す。
        let flavor: String
    }

    /// サーバーの `party_boss_id` と同じ並び。順番を変えるときは SQL も変える。
    static let catalog: [Boss] = [
        Boss(id: "sloth_slime", name: "サボリスライム", flavor: "「今日はいいか」とささやいて、ジムへ向かう足を重くする。"),
        Boss(id: "couch_golem", name: "ソファゴーレム", flavor: "ソファと一体化した巨体。座った人を立たせない。"),
        Boss(id: "snooze_dragon", name: "ネボウドラゴン", flavor: "二度寝の炎で朝トレの予定を焼きはらう。"),
        Boss(id: "junk_kraken", name: "ジャンククラーケン", flavor: "夜食とお菓子を八本の腕で差し出してくる。"),
    ]

    static func boss(id: String) -> Boss? { catalog.first { $0.id == id } }

    /// 撃破の報酬（テストステロンパワー）。サーバーの `party_boss_reward_energy` と揃える。
    static let rewardEnergy = 60
    /// 1パーティの上限人数。サーバーの `join_party` と揃える。
    static let maxMembers = 5
    /// 1人が入れるパーティの上限。サーバーの `party_max_per_user` と揃える（issue #130）。
    static let maxPartiesPerUser = 5
    /// パーティ名の上限（サーバーの `parties_name_length` と揃える）。
    static let maxNameLength = 20

    // MARK: - ランク（issue #133）

    /// ボスの強さ。前の週のうちにメンバーが投票し、日曜 23:59（JST）で締め切って決まる。
    /// 多数決で、同票は弱い方、票が無ければ中（サーバーの `party_tier`）。
    enum Tier: String, CaseIterable, Identifiable, Sendable {
        case weak, medium, strong

        var id: String { rawValue }

        var label: String {
            switch self {
            case .weak: return "弱い"
            case .medium: return "中くらい"
            case .strong: return "強い"
            }
        }

        /// 宝箱の EXP。サーバーの `party_boss_reward_exp` と揃える。
        var rewardExp: Int {
            switch self {
            case .weak: return 100
            case .medium: return 200
            case .strong: return 400
            }
        }

        /// HP の決め方の説明（投票の選択肢に添える）。
        var hpRule: String {
            switch self {
            case .weak: return "HP は週目標の合計の6割"
            case .medium: return "HP は週目標の合計"
            case .strong: return "全員が目標＋1回で倒せる"
            }
        }

        /// ランクで変わる HP（サーバーの `party_hp` の写し）。
        func hp(goals: [Int]) -> Int {
            guard !goals.isEmpty else { return 0 }
            let total = goals.reduce(0, +)
            switch self {
            case .weak: return max(1, Int((Double(total) * 0.6).rounded(.up)))
            case .medium: return total
            case .strong: return total + goals.count
            }
        }
    }

    // MARK: - 週

    /// 週の切り替わりの基準（月曜 0:00 JST）。全員で同じ週を共有するので端末のロケールに依らない。
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    /// その時刻が属する週の開始（月曜 0:00 JST）。
    static func weekStart(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// ボスの並びの起点（2026-01-05 月曜 0:00 JST）。
    static let rotationEpoch = Date(timeIntervalSince1970: 1_767_538_800)

    /// 週ごとのボス（サーバーの `party_boss_id` の写し）。
    static func bossId(forWeekStart weekStart: Date) -> String {
        let weeks = Int((weekStart.timeIntervalSince(rotationEpoch) / 604_800).rounded(.down))
        let index = ((weeks % catalog.count) + catalog.count) % catalog.count
        return catalog[index].id
    }

    /// 週が終わるまでの残り日数（今日を含む）。月曜なら 7、日曜なら 1。
    static func daysLeft(in weekStart: Date, now: Date) -> Int {
        let end = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: end).day ?? 0
        return min(max(days, 0), 7)
    }

    // MARK: - 状況

    struct Member: Identifiable, Equatable, Sendable {
        let id: UUID
        let displayName: String
        let avatarURL: String?
        let weeklyGoal: Int
        /// 今週完了したワークアウトの回数。
        let hits: Int
        /// 今週のジョブ（issue #137。0043 より前のサーバーは返さないので勇者）。
        var job: Job = .hero
        /// 本人が載せた見た目（未送信・旧版は nil。画面は ID から決まる色で描く）。
        var look: MemberLook?
        /// トレ中の配信（見える相手だけサーバーが返す）。応援の宛先。
        var liveSessionId: UUID?

        /// 基本のダメージ。1人あたり「目標 + 1」で頭打ち（サーバーの `party_attacks.base` と同じ）。
        /// 連携とスキルの上乗せは `Status.attacks` にある。
        var damage: Int { PartyBoss.cappedDamage(hits: hits, weeklyGoal: weeklyGoal) }
    }

    struct Status: Identifiable, Equatable, Sendable {
        let partyId: UUID
        /// メンバーが付けた名前（未設定は nil。表示は `title(for:)`）。
        let name: String?
        let weekStart: Date
        let bossId: String
        let hp: Int
        let damage: Int
        let defeated: Bool
        let claimed: Bool
        let members: [Member]
        /// 今週のボスのランク（0042 より前のサーバーは返さないので中とみなす）。
        var tier: Tier = .medium
        /// 撃破したときの宝箱の EXP。
        var rewardExp: Int = Tier.medium.rewardExp
        /// 翌週のランクへの票（いまのメンバーの分だけ）と、自分の票。
        var nextVotes: [Tier: Int] = [:]
        var myNextVote: Tier?
        /// 今週の攻撃（完了順。issue #137）。合計が `damage` になる。0043 より前のサーバーは返さない。
        var attacks: [Attack] = []

        var id: UUID { partyId }
        var boss: Boss? { PartyBoss.boss(id: bossId) }

        /// 画面に出す名前。名前が無ければ、自分以外のメンバー名を並べる（1人ならソロ）。
        func title(for userId: UUID) -> String {
            if let name, !name.isEmpty { return name }
            let others = members.filter { $0.id != userId }.map(\.displayName)
            guard !others.isEmpty else { return "ソロ" }
            let head = others.prefix(2).joined(separator: "・")
            return others.count > 2 ? "\(head) ほか\(others.count - 2)人と" : "\(head)と"
        }
        var remainingHP: Int { max(0, hp - damage) }
        var canInvite: Bool { members.count < PartyBoss.maxMembers }
        /// 宝箱を開けられる（倒したのにまだ受け取っていない）。育成タブのボタンのバッジにも使う。
        var hasUnclaimedChest: Bool { defeated && !claimed }
        /// 今週の連携攻撃の回数（＝連携が成立した日数）。
        var comboCount: Int { attacks.reduce(0) { $0 + $1.combo } }
        /// そのメンバーが今週スキルを出したか。
        func skillTriggered(by memberId: UUID) -> Bool {
            attacks.contains { $0.userId == memberId && $0.skill > 0 }
        }
        func member(_ id: UUID) -> Member? { members.first { $0.id == id } }
    }

    static func cappedDamage(hits: Int, weeklyGoal: Int) -> Int {
        min(max(hits, 0), max(weeklyGoal, 0) + 1)
    }

    /// `party_status` RPC の JSON を読む。パーティが無い（null）・壊れた応答は nil。
    static func status(fromJSON object: Any?) -> Status? {
        guard let row = object as? [String: Any],
              let partyId = (row["party_id"] as? String).flatMap(UUID.init(uuidString:)),
              let weekText = row["week_start"] as? String,
              let weekStart = parseTimestamp(weekText),
              let bossId = row["boss_id"] as? String
        else { return nil }
        let members = (row["members"] as? [[String: Any]] ?? []).compactMap { m -> Member? in
            guard let id = (m["user_id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            var member = Member(
                id: id,
                displayName: (m["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "メンバー",
                avatarURL: m["avatar_url"] as? String,
                weeklyGoal: (m["weekly_goal"] as? NSNumber)?.intValue ?? 3,
                hits: (m["hits"] as? NSNumber)?.intValue ?? 0
            )
            member.job = (m["job"] as? String).flatMap(Job.init(rawValue:)) ?? .hero
            member.look = MemberLook(json: m["look"])
            member.liveSessionId = (m["live_session_id"] as? String).flatMap(UUID.init(uuidString:))
            return member
        }
        let tier = (row["tier"] as? String).flatMap(Tier.init(rawValue:)) ?? .medium
        let votes = row["next_votes"] as? [String: Any] ?? [:]
        var status = Status(
            partyId: partyId,
            name: (row["name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            weekStart: weekStart,
            bossId: bossId,
            hp: (row["hp"] as? NSNumber)?.intValue ?? 0,
            damage: (row["damage"] as? NSNumber)?.intValue ?? 0,
            defeated: (row["defeated"] as? Bool) ?? false,
            claimed: (row["claimed"] as? Bool) ?? false,
            members: members
        )
        status.tier = tier
        status.rewardExp = (row["reward_exp"] as? NSNumber)?.intValue ?? tier.rewardExp
        status.nextVotes = Dictionary(uniqueKeysWithValues: Tier.allCases.map {
            ($0, (votes[$0.rawValue] as? NSNumber)?.intValue ?? 0)
        })
        status.myNextVote = (row["my_next_vote"] as? String).flatMap(Tier.init(rawValue:))
        status.attacks = (row["attacks"] as? [[String: Any]] ?? []).compactMap(Attack.init(json:))
        return status
    }

    /// 翌週のランクの投票の締め切り（今週の日曜 23:59:59 JST ＝ 翌週の月曜 0:00 の直前）。
    static func voteDeadline(forWeekStart weekStart: Date) -> Date {
        (calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart).addingTimeInterval(-1)
    }

    /// `my_parties` RPC の JSON（パーティの状況の配列）を読む。読めない要素は落とす。
    static func statuses(fromJSON object: Any?) -> [Status] {
        (object as? [Any] ?? []).compactMap(status(fromJSON:))
    }

    /// パーティ名の入力を整える（前後の空白を落とし、上限で切る）。空なら nil（未設定に戻す）。
    static func normalizedName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }

    // MARK: - 報酬と図鑑

    struct Reward: Equatable, Sendable {
        let weekStart: Date
        let bossId: String
        let energy: Int
        /// 撃破したランクと、そのランクの EXP（0042 より前の報酬は中・0）。
        var tier: Tier = .medium
        var exp: Int = 0
    }

    /// 報酬の行（`party_boss_rewards` / `claim_boss_reward`）を読む。
    static func reward(fromJSON object: Any?) -> Reward? {
        guard let row = object as? [String: Any],
              let weekText = row["week_start"] as? String,
              let weekStart = parseTimestamp(weekText),
              let bossId = row["boss_id"] as? String
        else { return nil }
        var reward = Reward(weekStart: weekStart, bossId: bossId, energy: (row["energy"] as? NSNumber)?.intValue ?? 0)
        reward.tier = (row["tier"] as? String).flatMap(Tier.init(rawValue:)) ?? .medium
        reward.exp = (row["exp"] as? NSNumber)?.intValue ?? 0
        return reward
    }

    /// 図鑑。ボスごとの撃破回数（未撃破は 0）。並びは `catalog` の順。
    static func trophies(from rewards: [Reward]) -> [(boss: Boss, defeats: Int)] {
        let counts = Dictionary(grouping: rewards, by: \.bossId).mapValues(\.count)
        return catalog.map { ($0, counts[$0.id] ?? 0) }
    }

    /// キャラの EXP への上乗せ（受け取った報酬の合計）。
    static func totalExp(from rewards: [Reward]) -> Int {
        rewards.reduce(0) { $0 + max(0, $1.exp) }
    }

    /// 遠征に使えるパワーへの上乗せ（受け取った報酬の合計）。
    static func totalEnergy(from rewards: [Reward]) -> Int {
        rewards.reduce(0) { $0 + max(0, $1.energy) }
    }

    /// PostgREST の timestamptz（小数秒あり/なし、`+09:00` / `Z` / `+00`）を読む。
    static func parseTimestamp(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        // Postgres の json は "2026-10-05T00:00:00+09:00" を返すが、"+00" のような短いオフセットも来うる。
        let normalized = text.range(of: #"[+-]\d{2}$"#, options: .regularExpression) != nil ? text + ":00" : text
        return withFraction.date(from: normalized) ?? plain.date(from: normalized)
    }
}
