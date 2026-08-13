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
    ///
    /// **祝う内容は完了した時点で確定させて丸ごと持つ**。育成タブ側で組み立て直さない。
    /// - 「前」はあとから復元できない。自己ベストの更新は行を増やさず既存の
    ///   `PersonalRecord.workoutId` を今回の id に付け替えるので、除外して組み直すと
    ///   元々あった自己ベストごと消えてしまう。
    /// - 「後」も、サマリーを開いている間に別端末の記録が同期されると動く。
    ///   それを今回のぶんとして数えないよう、完了直後の値で固定する。
    /// - 対象のワークアウトを見に行かないので、`@Query` の反映を待たずに出せる。
    struct Pending: Codable, Equatable, Sendable {
        let savedAt: Date
        let gain: Gain

        static let key = "gymnee.character.pendingCelebration"

        /// これより古い控えは出さない。落ちたあとに何日も前の記録を祝われても意味がない。
        static let maxAge: TimeInterval = 60 * 60

        func save(to defaults: UserDefaults = .standard) {
            guard let data = try? JSONEncoder().encode(self) else { return }
            defaults.set(data, forKey: Self.key)
        }

        /// 読み出して消す。取り出せたら一度きり（毎回開くたびに祝わない）。
        /// 壊れた値・古い値はここで捨て、次に持ち越さない。
        static func take(from defaults: UserDefaults = .standard, now: Date = .now) -> Pending? {
            defer { defaults.removeObject(forKey: key) }
            guard let data = defaults.data(forKey: key),
                  let pending = try? JSONDecoder().decode(Pending.self, from: data),
                  now.timeIntervalSince(pending.savedAt) < maxAge
            else { return nil }
            return pending
        }
    }

    /// 1 回で伸びた部位（多い順に並べて出す）。
    struct MuscleShare: Equatable, Sendable, Codable {
        let muscle: MuscleGroup
        let volumeKg: Double
    }

    /// この 1 回で育成がどう動いたか。**完了した時点で確定する**（あとから組み直さない）。
    /// `sheet(item:)` に渡すので Identifiable にする（同じ内容なら同じシート）。
    struct Gain: Equatable, Sendable, Codable, Identifiable {
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
