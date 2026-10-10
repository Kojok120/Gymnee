import CryptoKit
import Foundation

// 週ボスの戦闘（issue #137）。連携攻撃・ジョブ・攻撃の一覧と、戦闘画面の再生・セリフ。
//
// ダメージの正はサーバー（`supabase/migrations/0043_boss_battle.sql` の `party_attacks`）。
// ここに置く `PartyBoss.score` はその写しで、デモの組み立てと、SQL と同じシナリオでの突き合わせに使う
// （`scripts/sqltest/boss_battle_test.sql` ↔ `PartyBattleTests`）。規則を変えるときは両方を変える。

extension PartyBoss {

    // MARK: - 系統

    /// ワークアウトの系統（サーバーの `party_workout_category` と同じ分け方）。技名とジョブの元になる。
    enum Category: String, CaseIterable, Sendable {
        case upper, lower, core, cardio, full

        var label: String {
            switch self {
            case .upper: return "上半身"
            case .lower: return "下半身"
            case .core: return "体幹"
            case .cardio: return "有酸素"
            case .full: return "全身"
            }
        }

        /// 技名の候補。同じ攻撃はいつ見ても同じ技になるよう、攻撃の id で選ぶ。
        var moves: [String] {
            switch self {
            case .upper: return ["剛腕パンチ", "プレス斬り", "ダンベルスマッシュ"]
            case .lower: return ["スクワット・クラッシュ", "大地の踏みこみ", "ランジキック"]
            case .core: return ["体幹バスター", "鉄壁プランク", "腹筋スピン"]
            case .cardio: return ["疾風ダッシュ", "スタミナ連打", "風の足音"]
            case .full: return ["全身アタック", "フルパワー", "渾身の一撃"]
            }
        }

        func move(seed: String) -> String {
            let sum = seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
            return moves[sum % moves.count]
        }
    }

    // MARK: - ジョブ

    /// その週のジョブ。前の28日間に完了したワークアウトの系統で決まる（サーバーの `party_member_job`）。
    enum Job: String, CaseIterable, Sendable {
        case warrior, monk, thief, priest, hero

        var label: String {
            switch self {
            case .warrior: return "戦士"
            case .monk: return "武闘家"
            case .thief: return "盗賊"
            case .priest: return "僧侶"
            case .hero: return "勇者"
            }
        }

        var skillName: String {
            switch self {
            case .warrior: return "底力"
            case .monk: return "連撃"
            case .thief: return "先制"
            case .priest: return "祈り"
            case .hero: return "勇気"
            }
        }

        /// スキルの条件（1人週1回まで +1）。
        var skillRule: String {
            switch self {
            case .warrior: return "土曜か日曜に攻撃すると +1"
            case .monk: return "2日続けて攻撃すると +1"
            case .thief: return "月曜か火曜に攻撃すると +1"
            case .priest: return "仲間と同じ日に攻撃すると +1"
            case .hero: return "週目標の回数を達成すると +1"
            }
        }

        /// どう決まったか（メニューの説明に出す）。
        var origin: String {
            switch self {
            case .warrior: return "最近4週間、上半身が半分を超えた"
            case .monk: return "最近4週間、下半身が半分を超えた"
            case .thief: return "最近4週間、有酸素が半分を超えた"
            case .priest: return "最近4週間、体幹が半分を超えた"
            case .hero: return "最近4週間、偏りなく鍛えた（または記録がまだ無い）"
            }
        }

        var symbol: String {
            switch self {
            case .warrior: return "shield.lefthalf.filled"
            case .monk: return "figure.martial.arts"
            case .thief: return "hare.fill"
            case .priest: return "sparkles"
            case .hero: return "star.fill"
            }
        }

        /// 過去の系統からジョブを決める（`party_member_job` の写し）。
        /// 半分を**超える**系統があればそのジョブ。無ければ（同数・記録なし・全身が最多）勇者。
        static func decide(from categories: [Category]) -> Job {
            guard !categories.isEmpty else { return .hero }
            let counts = Dictionary(grouping: categories, by: { $0 }).mapValues(\.count)
            guard let top = counts.max(by: { ($0.value, $1.key.rawValue) < ($1.value, $0.key.rawValue) }),
                  top.value * 2 > categories.count
            else { return .hero }
            switch top.key {
            case .upper: return .warrior
            case .lower: return .monk
            case .cardio: return .thief
            case .core: return .priest
            case .full: return .hero
            }
        }
    }

    // MARK: - 攻撃

    /// 1回の攻撃（完了したワークアウト）とダメージの内訳。時刻は持たない（サーバーも日付までしか返さない）。
    struct Attack: Identifiable, Equatable, Sendable {
        /// ワークアウト id の md5（サーバーの `md5(workout_id::text)`）。再生済みかの判定に使う。
        let id: String
        let userId: UUID
        /// JST の日付（"2026-10-05"）。
        let day: String
        let category: Category
        /// 基本（1人あたり目標+1回目まで 1）。
        let base: Int
        /// ジョブのスキル（1人週1回）。
        let skill: Int
        /// 連携（その日に2人目の仲間が来た1撃）。
        let combo: Int

        var total: Int { base + skill + combo }

        init(id: String, userId: UUID, day: String, category: Category, base: Int, skill: Int, combo: Int) {
            self.id = id
            self.userId = userId
            self.day = day
            self.category = category
            self.base = base
            self.skill = skill
            self.combo = combo
        }

        init?(json row: [String: Any]) {
            guard let id = row["id"] as? String,
                  let userId = (row["user_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let day = row["day"] as? String
            else { return nil }
            self.init(
                id: id, userId: userId, day: day,
                category: (row["category"] as? String).flatMap(Category.init(rawValue:)) ?? .full,
                base: max(0, (row["base"] as? NSNumber)?.intValue ?? 0),
                skill: max(0, (row["skill"] as? NSNumber)?.intValue ?? 0),
                combo: max(0, (row["combo"] as? NSNumber)?.intValue ?? 0)
            )
        }

        /// JST の日付（`day`）を Date（その日の 0:00 JST）にする。読めなければ nil。
        var date: Date? { PartyBoss.dayFormatter.date(from: day) }
    }

    /// ワークアウト id から攻撃の id を作る（サーバーの `md5(workout_id::text)` と同じ）。
    static func attackId(workoutId: UUID) -> String {
        Insecure.MD5.hash(data: Data(workoutId.uuidString.lowercased().utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// JST の日付文字列（サーバーの `to_char(day, 'YYYY-MM-DD')`）。
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - ダメージの写し

    /// 集計前の攻撃。
    struct RawAttack: Sendable {
        let workoutId: UUID
        let userId: UUID
        let completedAt: Date
        let category: Category
    }

    /// 攻撃するメンバー（目標とその週のジョブ）。
    struct Fighter: Sendable {
        let id: UUID
        let weeklyGoal: Int
        let job: Job
    }

    /// 攻撃を完了順に並べ、ダメージの内訳を付ける（サーバーの `party_attacks` の写し）。
    /// メンバーでない人の攻撃は数えない。
    static func score(_ raw: [RawAttack], fighters: [Fighter]) -> [Attack] {
        let byId = Dictionary(fighters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // サーバーは (completed_at, workout_id) の順。uuid の大小は小文字の16進文字列の大小と同じ。
        let sorted = raw
            .filter { byId[$0.userId] != nil }
            .sorted { ($0.completedAt, $0.workoutId.uuidString.lowercased()) < ($1.completedAt, $1.workoutId.uuidString.lowercased()) }

        struct Row {
            let raw: RawAttack
            let fighter: Fighter
            let day: Date
            let seq: Int
            let firstOfUserDay: Bool
            let arrival: Int?
            let prevDay: Date?
        }
        var seqs: [UUID: Int] = [:]
        var lastDay: [UUID: Date] = [:]
        var visited: Set<String> = []
        var arrivals: [Date: Int] = [:]
        var rows: [Row] = []
        for attack in sorted {
            guard let fighter = byId[attack.userId] else { continue }
            let day = calendar.startOfDay(for: attack.completedAt)
            let seq = (seqs[attack.userId] ?? 0) + 1
            seqs[attack.userId] = seq
            let key = "\(day.timeIntervalSince1970)|\(attack.userId)"
            let first = !visited.contains(key)
            visited.insert(key)
            var arrival: Int?
            if first {
                arrival = (arrivals[day] ?? 0) + 1
                arrivals[day] = arrival
            }
            rows.append(Row(raw: attack, fighter: fighter, day: day, seq: seq,
                            firstOfUserDay: first, arrival: arrival, prevDay: lastDay[attack.userId]))
            lastDay[attack.userId] = day
        }

        var skilled: Set<UUID> = []
        return rows.map { row in
            let comboDay = (arrivals[row.day] ?? 0) >= 2
            let isoWeekday = isoWeekday(row.day)
            let condition: Bool
            switch row.fighter.job {
            case .warrior: condition = isoWeekday >= 6
            case .thief: condition = isoWeekday <= 2
            case .monk: condition = row.prevDay.map { calendar.date(byAdding: .day, value: 1, to: $0) == row.day } ?? false
            case .priest: condition = comboDay
            case .hero: condition = row.seq == row.fighter.weeklyGoal
            }
            var skill = 0
            if condition, !skilled.contains(row.fighter.id) {
                skilled.insert(row.fighter.id)
                skill = 1
            }
            return Attack(
                id: attackId(workoutId: row.raw.workoutId),
                userId: row.raw.userId,
                day: dayFormatter.string(from: row.day),
                category: row.raw.category,
                base: row.seq <= row.fighter.weeklyGoal + 1 ? 1 : 0,
                skill: skill,
                combo: row.firstOfUserDay && row.arrival == 2 ? 1 : 0
            )
        }
    }

    /// ISO の曜日（月曜 1 〜 日曜 7）。サーバーの `extract(isodow ...)`。
    static func isoWeekday(_ date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)  // 日曜 1 〜 土曜 7
        return weekday == 1 ? 7 : weekday - 1
    }

    // MARK: - 見た目

    /// 仲間の画面で描くための見た目（`profiles.character_look`）。ID だけを持ち、描画はアプリ側。
    /// 他人が書いた値なので、読むときは範囲に丸め、知らない ID は描画側が既定に落とす。
    struct MemberLook: Equatable, Sendable {
        var girth: Int
        var arm: Int
        var leg: Int
        var skinId: String
        var stage: Int
        var hairStyleId: String
        var accessoryId: String
        /// 部位（`Expedition.Slot.rawValue`）→ 装備の id。
        var equipped: [String: String]
        /// 性別（`CharacterGender.rawValue`。issue #141）。キーを足しただけなので版は据え置き。
        /// 古いアプリが送った見た目にはキーが無く、男性として読む。古いアプリは知らないキーを無視する。
        var gender: String = CharacterGender.male.rawValue

        static let version = 1
        private static let maxIdLength = 32

        init(build: CharacterBuild, skinId: String, stage: CharacterProgress.Stage,
             hairStyleId: String, accessoryId: String, equipped: [Expedition.Slot: Expedition.Item],
             gender: CharacterGender = .male) {
            self.gender = gender.rawValue
            girth = build.girth.rawValue
            arm = build.arm.rawValue
            leg = build.leg.rawValue
            self.skinId = skinId
            self.stage = stage.rawValue
            self.hairStyleId = hairStyleId
            self.accessoryId = accessoryId
            self.equipped = Dictionary(uniqueKeysWithValues: equipped.map { ($0.key.rawValue, $0.value.id) })
        }

        init?(json object: Any?) {
            guard let row = object as? [String: Any] else { return nil }
            func int(_ key: String, _ range: ClosedRange<Int>) -> Int {
                min(max((row[key] as? NSNumber)?.intValue ?? range.lowerBound, range.lowerBound), range.upperBound)
            }
            func text(_ key: String) -> String {
                String((row[key] as? String ?? "").prefix(Self.maxIdLength))
            }
            girth = int("girth", 0...(CharacterBuild.Girth.allCases.count - 1))
            arm = int("arm", 0...(CharacterBuild.Limb.allCases.count - 1))
            leg = int("leg", 0...(CharacterBuild.Limb.allCases.count - 1))
            stage = int("stage", 0...(CharacterProgress.Stage.allCases.count - 1))
            skinId = text("skin")
            hairStyleId = text("hair")
            accessoryId = text("acc")
            gender = CharacterGender(storedValue: row["g"] as? String).rawValue
            let gear = row["gear"] as? [String: Any] ?? [:]
            var equipped: [String: String] = [:]
            for slot in Expedition.Slot.allCases {
                if let id = gear[slot.rawValue] as? String { equipped[slot.rawValue] = String(id.prefix(Self.maxIdLength)) }
            }
            self.equipped = equipped
        }

        /// `set_character_look` に送る形。
        var json: [String: Any] {
            ["v": Self.version, "girth": girth, "arm": arm, "leg": leg, "skin": skinId,
             "stage": stage, "hair": hairStyleId, "acc": accessoryId, "gear": equipped, "g": gender]
        }

        /// 送り直しを避けるための指紋（キーの順を固定する）。
        var fingerprint: String {
            let gear = equipped.keys.sorted().map { "\($0)=\(equipped[$0] ?? "")" }.joined(separator: ",")
            return "v\(Self.version)|\(girth)\(arm)\(leg)|\(skinId)|\(stage)|\(hairStyleId)|\(accessoryId)|\(gear)|\(gender)"
        }

        var build: CharacterBuild {
            CharacterBuild(
                girth: CharacterBuild.Girth(rawValue: girth) ?? .slim,
                arm: CharacterBuild.Limb(rawValue: arm) ?? .thin,
                leg: CharacterBuild.Limb(rawValue: leg) ?? .thin
            )
        }

        var stageValue: CharacterProgress.Stage { CharacterProgress.Stage(rawValue: stage) ?? .rookie }

        var genderValue: CharacterGender { CharacterGender(storedValue: gender) }

        /// 装備。知らない id・部位の合わない id は着けない。
        var equippedItems: [Expedition.Slot: Expedition.Item] {
            var items: [Expedition.Slot: Expedition.Item] = [:]
            for slot in Expedition.Slot.allCases {
                if let id = equipped[slot.rawValue], let item = Expedition.item(id: id), item.slot == slot {
                    items[slot] = item
                }
            }
            return items
        }
    }
}

// MARK: - 戦闘画面の再生とセリフ

enum PartyBattle {

    /// 再生の1コマ（1回の攻撃）。
    struct Step: Identifiable, Equatable, Sendable {
        let attack: PartyBoss.Attack
        /// メッセージ窓に順に出す行。
        let lines: [String]
        let hpBefore: Int
        let hpAfter: Int

        var id: String { attack.id }
        var defeats: Bool { hpBefore > 0 && hpAfter == 0 }
    }

    struct Replay: Equatable, Sendable {
        let steps: [Step]
        /// 再生しきれずにまとめた古い攻撃の数（「ほか N 回の攻撃」）。
        let skipped: Int
        /// 再生を始めるときの残り HP。
        let startHP: Int

        static let empty = Replay(steps: [], skipped: 0, startHP: 0)
    }

    /// 画面を開いたときに再生する攻撃。まだ見ていない攻撃を完了順に、多いときは直近 `limit` 件だけ。
    /// 再生しない攻撃のダメージは先に引いておくので、再生の最後で残り HP がサーバーの値に揃う。
    static func replay(status: PartyBoss.Status, seen: Set<String>, userId: UUID, limit: Int = 6) -> Replay {
        let unseen = status.attacks.filter { !seen.contains($0.id) }
        let played = Array(unseen.suffix(max(0, limit)))
        let playedIds = Set(played.map(\.id))
        let alreadyDealt = status.attacks.filter { !playedIds.contains($0.id) }.reduce(0) { $0 + $1.total }
        let startHP = max(0, status.hp - alreadyDealt)
        var hp = startHP
        let steps = played.map { attack -> Step in
            let before = hp
            hp = max(0, hp - attack.total)
            return Step(
                attack: attack,
                lines: lines(for: attack, in: status, userId: userId, hpBefore: before, hpAfter: hp),
                hpBefore: before,
                hpAfter: hp
            )
        }
        return Replay(steps: steps, skipped: unseen.count - played.count, startHP: startHP)
    }

    /// 呼び名。自分は「あなた」。
    static func name(of memberId: UUID, in status: PartyBoss.Status, userId: UUID) -> String {
        if memberId == userId { return "あなた" }
        return status.member(memberId)?.displayName ?? "仲間"
    }

    /// 1回の攻撃のメッセージ。倒したあとの攻撃は「もう倒れている」とだけ言う（内訳を読ませても意味が無い）。
    static func lines(for attack: PartyBoss.Attack, in status: PartyBoss.Status, userId: UUID,
                      hpBefore: Int, hpAfter: Int) -> [String] {
        let bossName = status.boss?.name ?? "ボス"
        let who = name(of: attack.userId, in: status, userId: userId)
        var lines = ["\(who)の \(attack.category.move(seed: attack.id))！"]
        guard hpBefore > 0 else {
            return lines + ["しかし \(bossName)は もう たおれている"]
        }
        if attack.base > 0 {
            lines.append("\(bossName)に \(attack.base)の ダメージ！")
        } else if attack.total == 0 {
            lines.append("しかし 今週の上限を こえていた")
        }
        if attack.combo > 0 {
            // その日に先に来ていた仲間と連携した。
            let partner = status.attacks.first { $0.day == attack.day && $0.userId != attack.userId }
            let partnerName = partner.map { name(of: $0.userId, in: status, userId: userId) } ?? "仲間"
            lines.append("\(partnerName)と 連携攻撃！ さらに 1")
        }
        if attack.skill > 0 {
            let job = status.member(attack.userId)?.job ?? .hero
            lines.append("\(job.label)の \(job.skillName)！ さらに 1")
        }
        if hpAfter == 0 {
            lines.append("\(bossName)を たおした！")
        }
        return lines
    }

    /// 再生していないときにメッセージ窓に出す言葉（順に入れ替えて出す）。1つが1〜2行。
    static func idleMessages(status: PartyBoss.Status, userId: UUID, now: Date) -> [String] {
        let bossName = status.boss?.name ?? "ボス"
        if status.defeated {
            return status.hasUnclaimedChest
                ? ["宝箱が おちている！\nタップして 開けよう"]
                : ["\(bossName)を たおした！\n次のボスは 月曜に やってくる"]
        }
        var messages: [String] = []
        if status.remainingHP == 1 {
            messages.append("あと 1撃で たおせる！\nトレーニング 1回で とどめだ")
        } else {
            messages.append("\(bossName)が たちはだかる！\nのこり HP \(status.remainingHP)")
        }
        if isQuiet(status: status, now: now) {
            messages.append(taunt(bossId: status.bossId) + "\nだれかが トレーニングすれば 目をさます")
        }
        if let me = status.member(userId) {
            messages.append("あなたは \(me.job.label)。\(me.job.skillName):\n\(me.job.skillRule)")
        }
        if status.members.count > 1 {
            messages.append("仲間と 同じ日に トレーニングすると\n連携攻撃で さらに 1")
        } else {
            messages.append("仲間を さそうと\n連携攻撃が できるように なる")
        }
        let days = PartyBoss.daysLeft(in: status.weekStart, now: now)
        messages.append("あと \(days)日で\n\(bossName)は にげてしまう")
        return messages
    }

    /// 2日以上だれも攻撃していない（月曜はまだ始まったばかりなので静かでも言わない）。
    static func isQuiet(status: PartyBoss.Status, now: Date) -> Bool {
        let today = PartyBoss.calendar.startOfDay(for: now)
        let lastDay = status.attacks.compactMap(\.date).max() ?? status.weekStart
        let days = PartyBoss.calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        return days >= 2
    }

    /// ボスの挑発（由来に合わせる）。
    static func taunt(bossId: String) -> String {
        switch bossId {
        case "couch_golem": return "ソファゴーレムが ふかふかの 腕を ひろげている…"
        case "snooze_dragon": return "ネボウドラゴンが 二度寝の 炎を ためている…"
        case "junk_kraken": return "ジャンククラーケンが お菓子を ちらつかせている…"
        default: return "サボリスライムが「今日はいいか」と ささやいている…"
        }
    }

    // MARK: - 完了直後の「ボスに攻撃」

    /// 完了直後の祝いに出す「ボスに攻撃」。パーティに入っていなければ出さない。
    struct Strike: Equatable, Sendable {
        let bossId: String
        let tier: PartyBoss.Tier
        /// この1回が基本のダメージになったか（目標 + 1 回目まで）。
        let damaging: Bool
        let partyCount: Int

        var bossName: String { PartyBoss.boss(id: bossId)?.name ?? "ボス" }

        var title: String {
            damaging ? "\(bossName)に 1撃！" : "\(bossName)に 攻撃！"
        }

        var detail: String {
            guard damaging else {
                return "今週の上限（目標＋1回）を超えたので、基本のダメージは入りません。連携とスキルには数えます。"
            }
            return partyCount > 1
                ? "入っている\(partyCount)つのパーティのボスに、1撃ずつ入りました。"
                : "仲間と同じ日なら連携攻撃。ダンジョンで確かめよう。"
        }
    }

    /// 完了直後の「ボスに攻撃」を組み立てる。`weekHits` はこの1回を含む今週の完了回数（端末の記録が正）。
    static func strike(statuses: [PartyBoss.Status], weekHits: Int, weeklyGoal: Int) -> Strike? {
        guard let first = statuses.first, weekHits > 0 else { return nil }
        return Strike(
            bossId: first.bossId,
            tier: first.tier,
            damaging: weekHits <= max(weeklyGoal, 0) + 1,
            partyCount: statuses.count
        )
    }

    /// 今週（月曜 0:00 JST から）の完了回数。
    static func weekHits(completedAt: [Date], now: Date) -> Int {
        let start = PartyBoss.weekStart(for: now)
        let end = PartyBoss.calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return completedAt.filter { $0 >= start && $0 < end }.count
    }
}
