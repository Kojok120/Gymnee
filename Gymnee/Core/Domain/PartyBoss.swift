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

        /// ボスに入ったダメージ。1人あたり「目標 + 1」で頭打ち（サーバーの `party_damage` と同じ）。
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
            return Member(
                id: id,
                displayName: (m["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "メンバー",
                avatarURL: m["avatar_url"] as? String,
                weeklyGoal: (m["weekly_goal"] as? NSNumber)?.intValue ?? 3,
                hits: (m["hits"] as? NSNumber)?.intValue ?? 0
            )
        }
        return Status(
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
    }

    /// 報酬の行（`party_boss_rewards` / `claim_boss_reward`）を読む。
    static func reward(fromJSON object: Any?) -> Reward? {
        guard let row = object as? [String: Any],
              let weekText = row["week_start"] as? String,
              let weekStart = parseTimestamp(weekText),
              let bossId = row["boss_id"] as? String
        else { return nil }
        return Reward(weekStart: weekStart, bossId: bossId, energy: (row["energy"] as? NSNumber)?.intValue ?? 0)
    }

    /// 図鑑。ボスごとの撃破回数（未撃破は 0）。並びは `catalog` の順。
    static func trophies(from rewards: [Reward]) -> [(boss: Boss, defeats: Int)] {
        let counts = Dictionary(grouping: rewards, by: \.bossId).mapValues(\.count)
        return catalog.map { ($0, counts[$0.id] ?? 0) }
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
