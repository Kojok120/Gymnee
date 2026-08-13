import Foundation

/// 1 回のトレーニングが育成に与えた変化（純粋計算）。
///
/// 育成の値はすべて完了ワークアウトから毎回導出しているが、**それが動いた瞬間を見せる場所が
/// どこにも無かった**。記録を終えても画面に出るのは連続日数と総量だけで、
/// EXP もパワーもレベルも裏で動くだけだったため「トレーニングがどう育成に効くのか分からない」。
///
/// ここでは「この 1 回の前と後」の差分だけを組み立て、見せ方は View に任せる。
enum WorkoutGrowth {

    /// 完了サマリーを閉じてから育成タブで祝うまでの受け渡し。
    /// タブ切替をまたぐので、通知ではなく保存値で渡す（切替の順序に依存させない）。
    enum Pending {
        static let key = "gymnee.character.pendingCelebration"
    }

    /// 1 回で伸びた部位（多い順に並べて出す）。
    struct MuscleShare: Equatable, Sendable {
        let muscle: MuscleGroup
        let volumeKg: Double
    }

    /// この 1 回で育成がどう動いたか。
    /// `sheet(item:)` に渡すので Identifiable にする（同じ内容なら同じシート）。
    struct Gain: Equatable, Sendable, Identifiable {
        var id: String { "\(exp)-\(levelAfter.value)-\(stageAfter.rawValue)-\(prCount)" }

        /// この 1 回で得た EXP。
        let exp: Int
        /// この 1 回で貯まったテストステロンパワー。
        let energy: Int
        let levelBefore: CharacterProgress.Level
        let levelAfter: CharacterProgress.Level
        let stageBefore: CharacterProgress.Stage
        let stageAfter: CharacterProgress.Stage
        /// この 1 回で積んだ部位別ボリューム（多い順）。
        let muscles: [MuscleShare]
        /// この 1 回で更新した自己ベストの数。
        let prCount: Int

        var didLevelUp: Bool { levelAfter.value > levelBefore.value }
        var didEvolve: Bool { stageAfter > stageBefore }
    }

    /// 部位別ボリュームを多い順に並べる。0 と、部位に紐づかないもの（cardio 等）は落とす。
    static func muscleShares(volumeByMuscle: [MuscleGroup: Double]) -> [MuscleShare] {
        volumeByMuscle
            .filter { $0.value > 0 }
            .map { MuscleShare(muscle: $0.key, volumeKg: $0.value) }
            .sorted { lhs, rhs in
                // 量が同じなら部位の並び順で安定させる（毎回同じ順に出す）。
                lhs.volumeKg == rhs.volumeKg
                    ? lhs.muscle.rawValue < rhs.muscle.rawValue
                    : lhs.volumeKg > rhs.volumeKg
            }
    }

    /// 見出し。**起きたことのうち一番大きいものだけ**を言う。
    /// 進化・レベルアップ・それ以外で出し分け、乱数は使わない（同じ結果なら同じ言葉）。
    static func headline(for gain: Gain) -> String {
        if gain.didEvolve { return "\(gain.stageAfter.title) になった！" }
        if gain.didLevelUp { return "レベルが上がった！" }
        if gain.prCount > 0 { return "自己ベスト更新、お見事！" }
        return "頑張ったね！"
    }

    /// 見出しの下の一言。**何がどう効いたのか**を、この 1 回の数字で説明する。
    static func detail(for gain: Gain) -> String {
        var parts = ["今日の記録が \(gain.exp) EXP になった"]
        if gain.energy > 0 { parts.append("テストステロンパワーも \(gain.energy) 貯まった") }
        return parts.joined(separator: "。") + "。"
    }

    /// 伸びた部位の一言（最大 3 部位）。無ければ nil。
    static func muscleSummary(for gain: Gain, limit: Int = 3) -> String? {
        let names = gain.muscles.prefix(limit).map(\.muscle.label)
        guard !names.isEmpty else { return nil }
        return "効いたところ: " + names.joined(separator: "・")
    }

    /// 次の段階まで何が足りないか（`CharacterProgress.nextStage` の文言をそのまま使う）。
    /// 進化した直後は次の目標を出し、まだなら残りを出す。
    static func nextStageHint(_ next: CharacterProgress.NextStage?) -> String? {
        guard let next else { return nil }
        guard !next.unmet.isEmpty else { return "\(next.stage.title) の条件を満たしている" }
        return "次は \(next.stage.title)：" + next.unmet.joined(separator: " / ")
    }
}
