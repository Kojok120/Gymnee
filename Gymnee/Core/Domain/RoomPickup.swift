import Foundation

/// 部屋に落ちているグッズ（純粋計算）。
///
/// ねらいは**アプリを開く理由を毎日つくること**なので、記録がゼロでも基礎ドロップは必ず起きる。
/// そのうえで、前の週に頑張った人ほど落ちる量と質が上がる。
///
/// 原則（「強さは現実でしか買えない」）との折り合い:
/// - 基礎ドロップでもらえるのは**元気（遠征の燃料）だけ**。強さには一切効かない
/// - **EXP をくれるのはレアグッズだけ**で、その出現率は前週の成績で上下する。
///   つまり EXP は実質トレーニングに紐づいたまま
///
/// 湧く場所と中身は**時刻から決定的に導出**する（サーバーも常駐処理も要らない）。
/// 保存するのは「拾った」という事実だけ。
enum RoomPickup {

    // MARK: - 中身

    enum Rarity: String, CaseIterable, Sendable {
        case common, uncommon, rare

        var label: String {
            switch self {
            case .common: return "ノーマル"
            case .uncommon: return "レア"
            case .rare: return "エピック"
            }
        }
    }

    struct Item: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let rarity: Rarity
        /// 拾ったときに増える元気（遠征の燃料）。
        let energy: Int
        /// 拾ったときに増える EXP。**レアだけが 0 より大きい**。
        let experience: Int
    }

    /// 落ちているものの一覧。ジムで実際に手が伸びるものに寄せる。
    static let items: [Item] = [
        Item(id: "coffee", name: "コーヒー", rarity: .common, energy: 5, experience: 0),
        Item(id: "banana", name: "バナナ", rarity: .common, energy: 6, experience: 0),
        Item(id: "amino", name: "アミノ酸サプリ", rarity: .uncommon, energy: 10, experience: 0),
        Item(id: "protein-bar", name: "プロテインバー", rarity: .uncommon, energy: 12, experience: 0),
        Item(id: "creatine", name: "クレアチンサプリ", rarity: .rare, energy: 15, experience: 30),
    ]

    static func item(id: String) -> Item? { items.first { $0.id == id } }

    // MARK: - 落下の設計

    /// 湧く間隔（秒）。この単位で「落ちたか」を判定する。
    static let slotDuration: TimeInterval = 4 * 60 * 60

    /// 拾わずに残る時間。これを過ぎたグッズは消える（際限なく溜めさせない）。
    static let lifetime: TimeInterval = 48 * 60 * 60

    /// 同時に床へ出す上限。多すぎると部屋が散らかってキャラが見えなくなる。
    static let maxOnFloor = 5

    /// 基礎の落下率（1 スロットあたり）。記録がゼロでもこの確率で落ちる。
    static let baseDropChance: Double = 0.55

    /// レアが出る基礎確率（落ちた中での割合）。
    static let baseRareChance: Double = 0.06

    /// 前週の成績による倍率の上限。
    static let maxMultiplier: Double = 1.5

    /// 前の週の記録から落下率の倍率を出す。
    /// 目標を達成していれば 1.2 倍、超えていればさらに伸び、記録ゼロでも 1.0 を下回らない
    /// （落とさない、という罰は与えない）。
    static func multiplier(lastWeekCount: Int, weeklyGoal: Int) -> Double {
        guard weeklyGoal > 0 else { return 1 }
        let ratio = Double(max(0, lastWeekCount)) / Double(weeklyGoal)
        guard ratio.isFinite else { return 1 }
        // 0 回 → 1.0 / 目標ちょうど → 1.2 / 目標の 2 倍以上 → 1.5
        return min(maxMultiplier, 1 + 0.2 * min(ratio, 1) + 0.3 * max(0, min(ratio - 1, 1)))
    }

    // MARK: - 湧き（時刻から決定的に導出）

    /// 床に落ちている 1 個。`id` は「どのスロットで湧いたか」から決まるので、
    /// 拾った事実さえ保存すれば同じものが復活しない。
    struct Drop: Identifiable, Equatable, Sendable {
        /// スロット番号（湧いた時間帯の通し番号）。
        let slot: Int
        let item: Item
        /// 床の上の位置（0...1 の正規化。描画側が実寸へ変換する）。
        let position: CGPoint
        var id: Int { slot }
        /// 保存用の安定した識別子。
        var storageId: String { "\(slot)-\(item.id)" }
    }

    /// いま床に落ちているものを求める。
    ///
    /// - Parameters:
    ///   - now: 現在時刻
    ///   - seed: ユーザーごとの種（人によって落ちる物と場所が変わる）
    ///   - collected: すでに拾った `storageId`
    ///   - multiplier: 前週の成績による倍率（`multiplier(lastWeekCount:weeklyGoal:)`）
    static func drops(
        now: Date,
        seed: UInt64,
        collected: Set<String>,
        multiplier: Double = 1
    ) -> [Drop] {
        let currentSlot = slotIndex(for: now)
        let oldestSlot = currentSlot - Int(lifetime / slotDuration)
        guard currentSlot >= oldestSlot else { return [] }

        var result: [Drop] = []
        for slot in stride(from: currentSlot, through: oldestSlot, by: -1) {
            guard let drop = drop(slot: slot, seed: seed, multiplier: multiplier) else { continue }
            guard !collected.contains(drop.storageId) else { continue }
            result.append(drop)
            if result.count >= maxOnFloor { break }
        }
        return result
    }

    /// スロット番号（1970 年からの通し番号）。
    static func slotIndex(for date: Date) -> Int {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite else { return 0 }
        return Int((seconds / slotDuration).rounded(.down))
    }

    /// そのスロットに何が落ちたか。落ちていなければ nil。
    static func drop(slot: Int, seed: UInt64, multiplier: Double) -> Drop? {
        var rng = DeterministicRandom(seed: seed &+ 0x0DEC_0DE5 &* UInt64(bitPattern: Int64(slot)))
        let boost = max(1, multiplier.isFinite ? multiplier : 1)

        // 落ちたか。
        guard rng.unit() < min(0.95, baseDropChance * boost) else { return nil }

        // 何が落ちたか。レアの出現率だけを倍率で上げる（EXP を現実に紐づけたままにするため）。
        let rareChance = min(0.25, baseRareChance * boost)
        let roll = rng.unit()
        let rarity: Rarity
        if roll < rareChance {
            rarity = .rare
        } else if roll < rareChance + 0.30 {
            rarity = .uncommon
        } else {
            rarity = .common
        }

        let pool = items.filter { $0.rarity == rarity }
        guard !pool.isEmpty else { return nil }
        let item = pool[Int(rng.next() % UInt64(pool.count))]

        // 落ちている場所。キャラの歩く範囲より内側に置き、端で見切れないようにする。
        let position = CGPoint(
            x: 0.14 + rng.unit() * 0.72,
            y: 0.20 + rng.unit() * 0.66
        )
        return Drop(slot: slot, item: item, position: position)
    }

    // MARK: - 合計

    /// 拾った分の元気の合計。
    static func totalEnergy(collectedItemIds: [String]) -> Int {
        collectedItemIds.reduce(0) { $0 + (item(id: $1)?.energy ?? 0) }
    }

    /// 拾った分の EXP の合計。レア以外は 0 なので、ここが伸びるのは実質トレーニングした人だけ。
    static func totalExperience(collectedItemIds: [String]) -> Int {
        collectedItemIds.reduce(0) { $0 + (item(id: $1)?.experience ?? 0) }
    }
}
