import Foundation

/// 遠征（アプリ内で遊ぶ部分）の純粋ロジック。
///
/// 燃料は現実のワークアウトで貯まる「元気」だけ。遠征の成果でキャラが強くなることはなく、
/// 手に入るのは見た目（装備）のみ＝**強さは現実でしか買えない**。
/// サボると元気切れで遠征に出せなくなるが、キャラが弱くなることもない（罰ではなく休止）。
enum Expedition {

    // MARK: - 元気（燃料）

    static let energyPerSession = 20
    static let energyPerSet = 2
    /// 1 セッションで貯まる元気の上限。1 回の詰め込みより通う回数を評価する。
    static let energyCapPerSession = 60

    static func energyEarned(for session: CharacterProgress.SessionInput) -> Int {
        guard session.completedSets > 0 else { return 0 }
        return min(energyCapPerSession, energyPerSession + energyPerSet * session.completedSets)
    }

    static func totalEnergyEarned(sessions: [CharacterProgress.SessionInput]) -> Int {
        sessions.reduce(0) { $0 + energyEarned(for: $1) }
    }

    /// 手持ちの元気＝これまでに貯めた分 − 遠征に払った分。
    static func availableEnergy(sessions: [CharacterProgress.SessionInput], spent: Int) -> Int {
        max(0, totalEnergyEarned(sessions: sessions) - max(0, spent))
    }

    // MARK: - コース

    struct Course: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let energyCost: Int
        let durationMinutes: Int
        /// 解放レベル。
        let minLevel: Int
        /// レアリティ抽選の重み（`Rarity.allCases` と同じ順＝ノーマル / レア / エピック）。
        let weights: [Int]
    }

    static let courses: [Course] = [
        Course(id: "morning-hill", title: "朝の丘", subtitle: "軽い足慣らし", symbol: "sun.max.fill",
               energyCost: 20, durationMinutes: 30, minLevel: 1, weights: [80, 18, 2]),
        Course(id: "iron-forest", title: "鉄の森", subtitle: "手強い相手が出る", symbol: "tree.fill",
               energyCost: 45, durationMinutes: 120, minLevel: 3, weights: [60, 33, 7]),
        Course(id: "old-gym", title: "廃ジム探索", subtitle: "掘り出し物の宝庫", symbol: "building.columns.fill",
               energyCost: 80, durationMinutes: 360, minLevel: 8, weights: [40, 44, 16]),
        Course(id: "summit", title: "頂への遠征", subtitle: "丸一日の長征", symbol: "mountain.2.fill",
               energyCost: 140, durationMinutes: 1440, minLevel: 15, weights: [20, 50, 30]),
    ]

    static func course(id: String) -> Course? { courses.first { $0.id == id } }

    static func unlockedCourses(level: Int) -> [Course] { courses.filter { level >= $0.minLevel } }

    // MARK: - 進行

    static func finishDate(startedAt: Date, course: Course) -> Date {
        startedAt.addingTimeInterval(TimeInterval(course.durationMinutes) * 60)
    }

    /// 遠征の進行度（0...1）。
    static func progress(startedAt: Date, finishesAt: Date, now: Date) -> Double {
        let total = finishesAt.timeIntervalSince(startedAt)
        guard total.isFinite, total > 0 else { return 1 }
        let done = now.timeIntervalSince(startedAt)
        guard done.isFinite else { return 0 }
        return min(1, max(0, done / total))
    }

    /// 残り秒数（完了済みなら 0）。
    static func remainingSeconds(finishesAt: Date, now: Date) -> Int {
        let seconds = finishesAt.timeIntervalSince(now)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds.rounded(.up), 100_000_000))
    }

    /// 残り時間の表示（「あと2時間30分」形式。1 分未満は「まもなく」）。
    static func remainingText(finishesAt: Date, now: Date) -> String {
        let seconds = remainingSeconds(finishesAt: finishesAt, now: now)
        if seconds == 0 { return "帰還済み" }
        let minutes = seconds / 60
        if minutes < 1 { return "まもなく帰還" }
        if minutes < 60 { return "あと\(minutes)分" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "あと\(hours)時間" : "あと\(hours)時間\(rest)分"
    }

    // MARK: - 報酬（決定的な抽選）

    enum Rarity: String, CaseIterable, Sendable, Comparable {
        case common, rare, epic

        static func < (lhs: Rarity, rhs: Rarity) -> Bool {
            guard let l = allCases.firstIndex(of: lhs), let r = allCases.firstIndex(of: rhs) else { return false }
            return l < r
        }

        var label: String {
            switch self {
            case .common: return "ノーマル"
            case .rare: return "レア"
            case .epic: return "エピック"
            }
        }
    }

    /// 遠征で手に入る装備。強さには一切影響せず、見た目とコレクションのためだけに存在する。
    struct Item: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let symbol: String
        let rarity: Rarity
    }

    static let items: [Item] = [
        Item(id: "sports-drink", name: "スポーツドリンク", symbol: "drop.fill", rarity: .common),
        Item(id: "wristband", name: "リストバンド", symbol: "hand.raised.fill", rarity: .common),
        Item(id: "gym-bag", name: "ジムバッグ", symbol: "bag.fill", rarity: .common),
        Item(id: "protein-bar", name: "プロテインバー", symbol: "leaf.fill", rarity: .common),
        Item(id: "power-grip", name: "パワーグリップ", symbol: "bolt.fill", rarity: .rare),
        Item(id: "knee-sleeve", name: "ニースリーブ", symbol: "shield.fill", rarity: .rare),
        Item(id: "iron-plate", name: "鉄のプレート", symbol: "scalemass.fill", rarity: .rare),
        Item(id: "champion-belt", name: "チャンピオンベルト", symbol: "crown.fill", rarity: .epic),
        Item(id: "golden-dumbbell", name: "黄金のダンベル", symbol: "dumbbell.fill", rarity: .epic),
        Item(id: "legend-log", name: "伝説の記録帳", symbol: "sparkles", rarity: .epic),
    ]

    static func item(id: String) -> Item? { items.first { $0.id == id } }

    /// コースの重みに従って報酬を決める。同じ seed（＝遠征の id）なら常に同じ結果になるので、
    /// 受け取り前後で表示がぶれず、端末をまたいでも再現できる。
    static func reward(courseId: String, seed: UUID) -> Item {
        let target = course(id: courseId) ?? courses[0]
        var rng = SplitMix64(seed: seedValue(seed))
        let rarity = pickRarity(weights: target.weights, rng: &rng)
        let pool = items.filter { $0.rarity == rarity }
        guard !pool.isEmpty else { return items[0] }
        return pool[Int(rng.next() % UInt64(pool.count))]
    }

    private static func pickRarity(weights: [Int], rng: inout SplitMix64) -> Rarity {
        let all = Rarity.allCases
        let normalized = all.indices.map { i in i < weights.count ? max(0, weights[i]) : 0 }
        let total = normalized.reduce(0, +)
        guard total > 0 else { return .common }
        var roll = Int(rng.next() % UInt64(total))
        for (i, weight) in normalized.enumerated() where weight > 0 {
            roll -= weight
            if roll < 0 { return all[i] }
        }
        return .common
    }

    /// UUID → 64bit シード（FNV-1a）。
    private static func seedValue(_ uuid: UUID) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: uuid.uuid) { raw in
            for byte in raw {
                value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            }
        }
        return value
    }

    /// 決定的な擬似乱数（SplitMix64）。抽選を再現可能にするために自前で持つ。
    private struct SplitMix64 {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
