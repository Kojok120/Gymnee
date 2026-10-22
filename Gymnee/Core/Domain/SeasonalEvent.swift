import Foundation

/// 季節限定のボス（issue #155）。
///
/// ハロウィン・クリスマス・年末年始は、**その日を含む週**（月曜 0:00 JST 始まり）だけ週ボスが季節の姿になる。
/// 出し分けはアプリだけで行い、サーバーの規則（ボスの持ち回り・HP・ダメージ・報酬）は変えない。
/// サーバーは普段どおりのボス id を返し、アプリが読み込む時点で季節のボスに読み替える
/// （`PartyBoss.status(fromJSON:)` / `PartyBoss.reward(fromJSON:)`）。
/// 古いアプリの仲間には普段のボスが見えるが、HP も攻撃も同じものを共有している。
///
/// 季節のボスを倒して宝箱を開けると、その季節の限定装備がもらえる。所持は受け取った報酬の週から導出するので
/// 保存先を増やさずに済み、サーバーの報酬を読めば別の端末でも同じものを持っている。
enum SeasonalEvent: String, CaseIterable, Sendable {
    case halloween, christmas, newYear

    /// この日（JST の月・日）を含む週がイベントの週。
    var month: Int {
        switch self {
        case .halloween: return 10
        case .christmas: return 12
        case .newYear: return 1
        }
    }

    var dayOfMonth: Int {
        switch self {
        case .halloween: return 31
        case .christmas: return 25
        case .newYear: return 1
        }
    }

    var label: String {
        switch self {
        case .halloween: return "ハロウィン"
        case .christmas: return "クリスマス"
        case .newYear: return "お正月"
        }
    }

    // MARK: - ボス

    var boss: PartyBoss.Boss {
        switch self {
        case .halloween:
            return PartyBoss.Boss(id: "pumpkin_slime", name: "カボチャスライム",
                                  flavor: "「トリック・オア・サボり」とささやいて、お菓子とソファへ誘いこむ。")
        case .christmas:
            return PartyBoss.Boss(id: "santa_golem", name: "サンタゴーレム",
                                  flavor: "「今夜はパーティだから」と、プレゼントの山でジムへの道をふさぐ。")
        case .newYear:
            return PartyBoss.Boss(id: "newyear_dragon", name: "ネショウガツドラゴン",
                                  flavor: "「正月くらい寝ていよう」と、こたつの炎で初トレを焼きはらう。")
        }
    }

    /// 戦闘画面のメッセージ窓に出す挑発。
    var taunt: String {
        switch self {
        case .halloween: return "カボチャスライムが「お菓子をくれなきゃ サボらせるぞ」と わらっている…"
        case .christmas: return "サンタゴーレムが ごちそうの 袋を かかえている…"
        case .newYear: return "ネショウガツドラゴンが こたつで 寝息を たてている…"
        }
    }

    // MARK: - 限定装備

    /// 倒すともらえる限定装備。遠征の抽選には入らない（`Expedition.limitedItems`）。
    var rewardItem: Expedition.Item {
        switch self {
        case .halloween:
            return Expedition.Item(id: "witch-hat", name: "魔女の帽子", symbol: "sparkles", rarity: .epic, slot: .head)
        case .christmas:
            return Expedition.Item(id: "santa-hat", name: "サンタ帽", symbol: "sparkles", rarity: .epic, slot: .head)
        case .newYear:
            return Expedition.Item(id: "hinomaru-band", name: "日の丸はちまき", symbol: "sparkles", rarity: .epic, slot: .head)
        }
    }

    // MARK: - 判定

    /// その週がイベントの週なら、そのイベント。週は月曜 0:00 JST 始まり（`PartyBoss.calendar`）。
    static func event(forWeekStart weekStart: Date) -> SeasonalEvent? {
        let calendar = PartyBoss.calendar
        let start = PartyBoss.weekStart(for: weekStart)
        #if DEBUG
        // 撮影・確認用。`-gymneeSeasonalEvent halloween` で今週をそのイベントの週として扱う（製品ビルドには無い）。
        if let forced = UserDefaults.standard.string(forKey: "gymneeSeasonalEvent").flatMap(SeasonalEvent.init(rawValue:)),
           start == PartyBoss.weekStart(for: .now) {
            return forced
        }
        #endif
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
        // 年をまたぐ週（年末年始）があるので、週の初日と最終日の両方の年で探す。
        let years = Set([start, end.addingTimeInterval(-1)].map { calendar.component(.year, from: $0) })
        for event in allCases {
            for year in years {
                guard let day = calendar.date(from: DateComponents(year: year, month: event.month, day: event.dayOfMonth))
                else { continue }
                if day >= start && day < end { return event }
            }
        }
        return nil
    }

    /// その時刻が属する週のイベント。
    static func event(at date: Date) -> SeasonalEvent? {
        event(forWeekStart: PartyBoss.weekStart(for: date))
    }

    /// 季節のボスの id からイベントを引く。
    static func event(bossId: String) -> SeasonalEvent? {
        allCases.first { $0.boss.id == bossId }
    }

    /// 画面に出すボスの id。イベントの週は季節のボス、それ以外はサーバー（または週の割り当て）のまま。
    static func displayBossId(serverBossId: String, weekStart: Date) -> String {
        event(forWeekStart: weekStart)?.boss.id ?? serverBossId
    }

    /// 受け取った報酬から、持っている限定装備の id を導出する。
    /// 報酬の行のボス id ではなく**週**で判定する（古い控えや、読み替える前の id でも取りこぼさない）。
    static func ownedItemIds(rewards: [PartyBoss.Reward]) -> Set<String> {
        Set(rewards.compactMap { event(forWeekStart: $0.weekStart)?.rewardItem.id })
    }
}
