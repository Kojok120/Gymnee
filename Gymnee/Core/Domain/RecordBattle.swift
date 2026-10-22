import Foundation

/// 記録画面の戦闘（issue #155）。
///
/// ゲームは育成タブの中にしかなく、ジムで一番長く開く記録画面は普通の記録ツールだった。
/// 記録画面の下に小さな戦闘の帯を置き、**セットを記録するたびに主人公が技を出す**。
///
/// 週ボスのダメージの規則（1 回の記録で 1 撃。`PartyBoss.score`）は変えない。帯では、今日の記録で削る
/// 「1 撃ぶん」の HP を、セットを重ねるたびに少しずつ削って見せる（`chipProgress`）。記録を終えると
/// とどめの一撃で、その 1 撃ぶんが実際に減る（サーバーが数える）。
///
/// 相手は 3 通り:
/// - 初めての 1 回はチュートリアルのちびスライム（1 セットで倒れて宝箱が出る）
/// - パーティに入っていて、今日の 1 回がダメージになる週は、その週の週ボス
/// - それ以外（パーティが無い・もう倒した・今週はダメージの上限）は練習用のかかし
enum RecordBattle {

    enum DummyReason: Equatable, Sendable {
        case noParty
        case defeated
        case capped
    }

    enum Opponent: Equatable, Sendable {
        case tutorial
        case boss(bossId: String, tier: PartyBoss.Tier, remainingHP: Int, totalHP: Int)
        case dummy(DummyReason)

        /// 帯に出す名前。
        var name: String {
            switch self {
            case .tutorial: return "ちびスライム"
            case .boss(let bossId, _, _, _): return PartyBoss.boss(id: bossId)?.name ?? "今週のボス"
            case .dummy: return "練習用のかかし"
            }
        }
    }

    /// 相手を決める。
    /// - Parameters:
    ///   - completedWorkouts: これまでに完了したワークアウトの回数（今の記録は含まない）。
    ///   - tutorialDone: チュートリアルの宝箱をもう開けたか。
    ///   - status: 選んでいるパーティの今週の状況（パーティが無い・読めていなければ nil）。
    ///   - weekHits: 今週これまでに完了した回数（今の記録は含まない）。
    ///   - weeklyGoal: 週の目標回数。
    static func opponent(completedWorkouts: Int, tutorialDone: Bool, status: PartyBoss.Status?,
                         weekHits: Int, weeklyGoal: Int) -> Opponent {
        if completedWorkouts == 0 && !tutorialDone { return .tutorial }
        guard let status else { return .dummy(.noParty) }
        if status.defeated { return .dummy(.defeated) }
        // 今日の 1 回が基本のダメージになるのは「目標 + 1 回目」まで（`PartyBoss.cappedDamage`）。
        guard weekHits + 1 <= max(0, weeklyGoal) + 1 else { return .dummy(.capped) }
        return .boss(bossId: status.bossId, tier: status.tier, remainingHP: status.remainingHP, totalHP: status.hp)
    }

    // MARK: - 削り

    /// 今日の記録で見込むセット数。今日の計画があればその合計、無ければ最近の記録の中央値、どちらも無ければ 12。
    static func expectedSets(plannedSets: Int?, recentSetCounts: [Int]) -> Int {
        if let plannedSets, plannedSets > 0 { return min(30, max(3, plannedSets)) }
        let recent = recentSetCounts.filter { $0 > 0 }.sorted()
        guard !recent.isEmpty else { return 12 }
        return min(30, max(3, recent[recent.count / 2]))
    }

    /// 1 撃ぶんの HP をどこまで削ったか（0...1）。見込みのセット数に届いたら削りきり。
    static func chipProgress(sets: Int, expectedSets: Int) -> Double {
        guard expectedSets > 0 else { return 1 }
        return min(1, max(0, Double(sets) / Double(expectedSets)))
    }

    // MARK: - 1 セットの一撃

    /// 1 セットの一撃の数字。重さがあれば挙げた量（kg × 回）、自重は回数、時間の種目は秒。
    static func strikeLabel(weight: Double, reps: Int, duration: Int?) -> String {
        if let duration, duration > 0 { return "\(duration)秒" }
        if weight.isFinite, weight > 0, reps > 0 {
            let volume = weight * Double(reps)
            guard volume.isFinite else { return "\(reps)回" }
            return "\(Int(volume.rounded()))"
        }
        return "\(max(0, reps))回"
    }

    /// 1 セットの一撃でメッセージ窓に出す言葉。自己ベストは会心の一撃。
    static func strikeLine(event: Technique.Event, isPR: Bool) -> String {
        let base: String
        switch event {
        case .learned(let name): base = "\(name)を おぼえた！"
        case .leveledUp(let name, let level): base = "\(name)が Lv.\(level)に あがった！"
        case .used(let name, _): base = "\(name)！"
        }
        return isPR ? "会心の一撃！ " + base : base
    }

    // MARK: - とどめ

    /// 記録を終えたときの言葉。週ボスは残りが 1 撃以下なら倒したことにする（実際の判定はサーバー）。
    static func finishLine(opponent: Opponent) -> String {
        switch opponent {
        case .tutorial:
            return "ちびスライムを たおした！"
        case .boss(let bossId, _, let remaining, _):
            let name = PartyBoss.boss(id: bossId)?.name ?? "ボス"
            return remaining <= 1 ? "とどめの一撃！ \(name)を たおした！" : "とどめの一撃！ \(name)に 1ダメージ！"
        case .dummy:
            return "とどめの一撃！ かかしを たおした！"
        }
    }

    /// 記録画面で戦うかの設定（未設定は ON）。
    static let enabledKey = "gymnee.recordBattleEnabled"

    // MARK: - チュートリアル

    /// チュートリアルの宝箱の中身（テストステロンパワー）。最初の遠征（朝の丘 = 30）にちょうど出られる量。
    static let tutorialChestEnergy = 30

    /// チュートリアルの宝箱を開けたかの保存キー（端末ごと。強さには効かない燃料なので端末内で足りる）。
    static let tutorialChestKey = "gymnee.tutorial.chestOpened"

    /// パワーへの上乗せ（開けていれば宝箱の分）。
    static func tutorialBonus(opened: Bool) -> Int { opened ? tutorialChestEnergy : 0 }
}
