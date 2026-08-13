import Foundation

/// 育成キャラの成長ロジック（純粋関数）。
///
/// 設計原則は 2 つ。
/// 1. **現実だけがエンジン**: 入力は完了したワークアウトのみ。アプリ内の遊び（遠征）では一切強くならない。
///    こうしないと「アプリ内で完結してしまい、自分が筋トレをする意味が消える」。
/// 2. **成長曲線はゲームが設計する**: 現実の記録をそのまま写すと変化が乏しくて続かないため、
///    体感速度を 3 層に分ける。
///    - 毎回変わる: レベル（努力量＝セット数・ボリューム・PR で必ず前進する）
///    - 節目で激変: 進化段階（レベル・自己ベスト・週次ストリークのマイルストーン）
///    - 現実の写し: 部位別ステータス（情報としては残すが、成長の主役にはしない）
enum CharacterProgress {

    /// 1 セッション（完了したワークアウト 1 件）の集計入力。SwiftData には依存しない。
    struct SessionInput: Equatable, Sendable {
        var completedAt: Date
        var completedSets: Int
        var volumeKg: Double
        var prCount: Int

        init(completedAt: Date, completedSets: Int, volumeKg: Double, prCount: Int = 0) {
            self.completedAt = completedAt
            self.completedSets = completedSets
            self.volumeKg = volumeKg
            self.prCount = prCount
        }
    }

    // MARK: - EXP（毎回変わる層）

    /// 「ジムに行った」事実そのものへの報酬。内容が軽い日でも必ず前進させる。
    static let baseExpPerSession = 40
    static let expPerSet = 6
    static let expPerPR = 120
    /// 1 セッションのボリューム EXP の上限。1 回の詰め込みより通う回数を評価する。
    static let volumeExpCap = 300

    /// ボリューム EXP。平方根で逓減させ、高重量者の独走と初心者の停滞を同時に避ける。
    /// 目安: 1t で 32 / 10t で 101 / 88t 以上で上限。
    static func volumeExp(_ volumeKg: Double) -> Int {
        guard volumeKg.isFinite, volumeKg > 0 else { return 0 }
        let raw = (volumeKg / 1000).squareRoot() * 32
        guard raw.isFinite else { return 0 }
        return min(volumeExpCap, Int(raw))
    }

    /// 1 セッションで得られる EXP。セットが 1 つも無い記録は「行っていない」扱いで 0。
    static func experience(for session: SessionInput) -> Int {
        guard session.completedSets > 0 else { return 0 }
        return baseExpPerSession
            + expPerSet * session.completedSets
            + volumeExp(session.volumeKg)
            + expPerPR * max(0, session.prCount)
    }

    static func totalExperience(sessions: [SessionInput]) -> Int {
        sessions.reduce(0) { $0 + experience(for: $1) }
    }

    /// 完了ワークアウトの EXP に、部屋で拾ったレアグッズの EXP を足した合計。
    ///
    /// **原則の例外はここだけ**。「現実だけがエンジン」を厳密に貫くとアプリを開く理由が作れないため、
    /// リテンションの都合で穴を 1 つ空けている。ただし EXP をくれるのはレアグッズだけで、
    /// その出現率は前週の記録で上下する（`RoomPickup`）。結果として、伸ばせるのは実際に通った人だけ。
    static func totalExperience(sessions: [SessionInput], pickupBonus: Int) -> Int {
        totalExperience(sessions: sessions) + max(0, pickupBonus)
    }

    // MARK: - レベル

    struct Level: Equatable, Sendable, Codable {
        /// 現在のレベル（1 始まり）。
        var value: Int
        /// 現在のレベル内で獲得済みの EXP。
        var expIntoLevel: Int
        /// 次のレベルまでに必要な EXP（上限レベルでは 0）。
        var expForNextLevel: Int

        /// 次のレベルまでの進捗（0...1）。上限レベルでは 1。
        var progress: Double {
            guard expForNextLevel > 0 else { return 1 }
            return min(1, max(0, Double(expIntoLevel) / Double(expForNextLevel)))
        }
    }

    /// 上限レベル。累積 EXP が壊れた値でも走り続けないための歯止めを兼ねる。
    static let maxLevel = 200

    /// `level` から次のレベルへ上がるのに必要な EXP。緩やかに逓増させる（頭打ちにはしない）。
    static func expForLevel(_ level: Int) -> Int {
        200 + max(0, level - 1) * 60
    }

    static func level(totalExperience: Int) -> Level {
        var remaining = max(0, totalExperience)
        var current = 1
        while current < maxLevel {
            let need = expForLevel(current)
            if remaining < need { break }
            remaining -= need
            current += 1
        }
        return Level(
            value: current,
            expIntoLevel: remaining,
            expForNextLevel: current < maxLevel ? expForLevel(current) : 0
        )
    }

    // MARK: - 進化段階（節目で激変する層）

    enum Stage: Int, CaseIterable, Sendable, Comparable, Codable {
        case rookie = 0, trainee, challenger, veteran, champion, legend

        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .rookie: return "ルーキー"
            case .trainee: return "トレーニー"
            case .challenger: return "チャレンジャー"
            case .veteran: return "ベテラン"
            case .champion: return "チャンピオン"
            case .legend: return "レジェンド"
            }
        }

        var symbol: String {
            switch self {
            case .rookie: return "figure.walk"
            case .trainee: return "figure.strengthtraining.traditional"
            case .challenger: return "flame.fill"
            case .veteran: return "shield.fill"
            case .champion: return "trophy.fill"
            case .legend: return "crown.fill"
            }
        }
    }

    /// 進化の条件。3 つすべてを満たすとその段階に到達する。
    /// 現実の記録は簡単には伸びないので、進化は「めったに起きない代わりに大きく変わる」出来事に置く。
    struct Requirement: Equatable, Sendable {
        let stage: Stage
        let level: Int
        let prCount: Int
        let weeklyStreakWeeks: Int
    }

    static let requirements: [Requirement] = [
        Requirement(stage: .rookie, level: 1, prCount: 0, weeklyStreakWeeks: 0),
        Requirement(stage: .trainee, level: 5, prCount: 1, weeklyStreakWeeks: 1),
        Requirement(stage: .challenger, level: 12, prCount: 5, weeklyStreakWeeks: 3),
        Requirement(stage: .veteran, level: 25, prCount: 15, weeklyStreakWeeks: 8),
        Requirement(stage: .champion, level: 45, prCount: 40, weeklyStreakWeeks: 16),
        Requirement(stage: .legend, level: 70, prCount: 80, weeklyStreakWeeks: 30),
    ]

    /// 条件を満たした最上位の段階。
    static func stage(level: Int, prCount: Int, weeklyStreakWeeks: Int) -> Stage {
        var result = Stage.rookie
        for r in requirements
        where level >= r.level && prCount >= r.prCount && weeklyStreakWeeks >= r.weeklyStreakWeeks {
            result = max(result, r.stage)
        }
        return result
    }

    /// 次の進化段階と、まだ満たしていない条件（UI で「あと何が足りないか」を出す）。
    struct NextStage: Equatable, Sendable, Codable {
        let stage: Stage
        /// 未達の条件の説明。空＝次の段階の条件はすべて満たしている。
        let unmet: [String]
    }

    static func nextStage(level: Int, prCount: Int, weeklyStreakWeeks: Int) -> NextStage? {
        let current = stage(level: level, prCount: prCount, weeklyStreakWeeks: weeklyStreakWeeks)
        guard let next = requirements.first(where: { $0.stage.rawValue == current.rawValue + 1 }) else { return nil }
        var unmet: [String] = []
        if level < next.level { unmet.append("Lv.\(next.level)まであと\(next.level - level)") }
        if prCount < next.prCount { unmet.append("自己ベストあと\(next.prCount - prCount)") }
        if weeklyStreakWeeks < next.weeklyStreakWeeks {
            unmet.append("連続\(next.weeklyStreakWeeks)週まであと\(next.weeklyStreakWeeks - weeklyStreakWeeks)")
        }
        return NextStage(stage: next.stage, unmet: unmet)
    }

    // MARK: - 部位別ステータス（現実の写し）

    enum Axis: String, CaseIterable, Sendable {
        case push, pull, legs, arms, core

        var label: String {
            switch self {
            case .push: return "押す力"
            case .pull: return "引く力"
            case .legs: return "脚力"
            case .arms: return "腕力"
            case .core: return "体幹"
            }
        }

        var symbol: String {
            switch self {
            case .push: return "figure.strengthtraining.traditional"
            case .pull: return "figure.rower"
            case .legs: return "figure.run"
            case .arms: return "hand.raised.fill"
            case .core: return "figure.core.training"
            }
        }
    }

    /// 部位 → ステータス軸。有酸素・全身・その他は特定の軸に寄せない。
    static func axis(for group: MuscleGroup) -> Axis? {
        switch group {
        case .chest, .shoulders: return .push
        case .back: return .pull
        case .legs, .glutes: return .legs
        case .arms: return .arms
        case .abs, .core: return .core
        case .cardio, .fullBody, .other: return nil
        }
    }

    /// 累積ボリューム（kg）→ ステータス値（0〜99）。対数スケールで序盤は動き、上位ほど詰まる。
    /// 目安: 1t で 9 / 10t で 31 / 100t で 60 / 1,000t で 90。
    static func statValue(volumeKg: Double) -> Int {
        guard volumeKg.isFinite, volumeKg > 0 else { return 0 }
        let scaled = 30 * log10(1 + volumeKg / 1000)
        guard scaled.isFinite else { return 0 }
        return min(99, max(1, Int(scaled)))
    }

    /// 部位別ボリュームから 5 軸のステータスを組み立てる（全軸そろえて返す）。
    static func stats(volumeByMuscle: [MuscleGroup: Double]) -> [Axis: Int] {
        var totals: [Axis: Double] = [:]
        for (group, volume) in volumeByMuscle {
            guard let axis = axis(for: group), volume.isFinite, volume > 0 else { continue }
            totals[axis, default: 0] += volume
        }
        var result: [Axis: Int] = [:]
        for axis in Axis.allCases {
            result[axis] = statValue(volumeKg: totals[axis] ?? 0)
        }
        return result
    }
}
