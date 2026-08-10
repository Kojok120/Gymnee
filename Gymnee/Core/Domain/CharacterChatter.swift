import Foundation

/// キャラのひとこと（純粋関数）。
///
/// シーンを「眺めるだけの飾り」で終わらせないための仕掛け。キャラが今の状況を口にすることで、
/// 画面を開いた瞬間に「次に何をすればいいか」が分かる。数字を読ませる代わりに喋らせる。
///
/// 優先順位は**行動につながるものほど上**。今すぐ触れる用事（受け取り・記録）を先に出し、
/// 用事が無いときだけ雑談に落ちる。
enum CharacterChatter {

    /// 遠征の状態。
    enum ExpeditionState: Equatable, Sendable {
        /// 出ていない。
        case idle
        /// 遠征中（残り時間の表示つき）。
        case running(remaining: String)
        /// 帰ってきて受け取り待ち。
        case awaitingClaim
    }

    /// ひとことを決めるのに要る材料。すべて呼び出し側が現実の記録から用意する。
    struct Context: Equatable, Sendable {
        var recordedToday: Bool
        /// 今週の記録回数と目標。
        var weeklyDone: Int
        var weeklyGoal: Int
        /// 連続達成週。
        var streakWeeks: Int
        /// 手持ちの元気。
        var energy: Int
        /// いま出せる遠征の最小コスト（出せるコースが無ければ nil）。
        var cheapestCourseCost: Int?
        var expedition: ExpeditionState
        /// 今日いっしょに記録した仲間。
        var partners: [String]
        /// 次の進化に足りていない条件。
        var nextStageUnmet: [String]
        /// 最後に記録してからの日数（記録が 1 件も無ければ nil）。
        var daysSinceLastWorkout: Int?

        init(
            recordedToday: Bool = false,
            weeklyDone: Int = 0,
            weeklyGoal: Int = 3,
            streakWeeks: Int = 0,
            energy: Int = 0,
            cheapestCourseCost: Int? = nil,
            expedition: ExpeditionState = .idle,
            partners: [String] = [],
            nextStageUnmet: [String] = [],
            daysSinceLastWorkout: Int? = nil
        ) {
            self.recordedToday = recordedToday
            self.weeklyDone = weeklyDone
            self.weeklyGoal = weeklyGoal
            self.streakWeeks = streakWeeks
            self.energy = energy
            self.cheapestCourseCost = cheapestCourseCost
            self.expedition = expedition
            self.partners = partners
            self.nextStageUnmet = nextStageUnmet
            self.daysSinceLastWorkout = daysSinceLastWorkout
        }
    }

    /// ひとことと、それに紐づく用事。用事があるものはタップで該当画面へ飛ばす。
    struct Line: Equatable, Sendable {
        let text: String
        /// タップしたときに開くもの。nil＝ただの雑談。
        let action: Action?

        enum Action: Equatable, Sendable {
            /// 記録をはじめる。
            case startWorkout
            /// 遠征シートを開く。
            case expedition
            /// 帰ってきた遠征を受け取る。
            case claim
        }
    }

    /// いまのひとこと。`seed` は雑談のバリエーション選び（時間で変えると喋る内容が変わる）。
    static func line(for context: Context, seed: UInt64 = 0) -> Line {
        // 1. 受け取り待ちの戦利品。放置させない。
        if context.expedition == .awaitingClaim {
            return Line(text: "遠征から戻ったよ。荷物、開けてみて", action: .claim)
        }

        // 2. 今日まだ記録していない。週の目標に手が届くならそれを言う。
        if !context.recordedToday {
            let remaining = context.weeklyGoal - context.weeklyDone
            if remaining == 1 {
                return Line(text: "あと1回で今週の目標。行こう", action: .startWorkout)
            }
            if remaining > 1 {
                return Line(text: "今週はあと\(remaining)回。まだ間に合う", action: .startWorkout)
            }
            if !context.partners.isEmpty {
                return Line(text: "\(partnerLabel(context.partners))はもう終わってるよ", action: .startWorkout)
            }
            return Line(text: "今日はまだ体を動かしてないね", action: .startWorkout)
        }

        // 3. 今日いっしょに記録した仲間がいる。遠征に出すと当たりが良くなる。
        if !context.partners.isEmpty, context.expedition == .idle, canStartExpedition(context) {
            return Line(text: "\(partnerLabel(context.partners))と一緒だった日は、いい物が出るらしい", action: .expedition)
        }

        // 4. 元気が余っている。遠征に出せる。
        if context.expedition == .idle, canStartExpedition(context) {
            return Line(text: "元気が\(context.energy)たまってる。どこか行ってきていい？", action: .expedition)
        }

        // 5. 遠征中。残り時間を教える。
        if case .running(let remaining) = context.expedition {
            return Line(text: "遠征中。\(remaining)で戻るよ", action: nil)
        }

        // 6. 次の進化まであと少し。
        if let unmet = context.nextStageUnmet.first {
            return Line(text: "\(unmet)。もう少しなんだ", action: nil)
        }

        // 7. 用事なし。今日の頑張りをねぎらう。
        return smallTalk(context: context, seed: seed)
    }

    // MARK: - 雑談

    private static func smallTalk(context: Context, seed: UInt64) -> Line {
        var options: [String] = [
            "今日はよく動いたね",
            "いい汗かいた",
            "この調子でいこう",
        ]
        if context.streakWeeks >= 2 {
            options.append("\(context.streakWeeks)週続いてる。すごいよ")
        }
        if context.weeklyDone >= context.weeklyGoal, context.weeklyGoal > 0 {
            options.append("今週の目標、もう達成してる")
        }
        if context.energy > 0 {
            options.append("元気が\(context.energy)ある。まだ動ける")
        }
        var rng = DeterministicRandom(seed: seed)
        let index = Int(rng.next() % UInt64(options.count))
        return Line(text: options[index], action: nil)
    }

    /// いま遠征に出せるか。
    private static func canStartExpedition(_ context: Context) -> Bool {
        guard let cost = context.cheapestCourseCost else { return false }
        return context.energy >= cost
    }

    /// 仲間の名前の並べ方（3 人以上は「ほか」でまとめる）。
    static func partnerLabel(_ partners: [String]) -> String {
        guard !partners.isEmpty else { return "" }
        if partners.count <= 2 { return partners.joined(separator: "と") }
        return "\(partners[0])たち"
    }
}
