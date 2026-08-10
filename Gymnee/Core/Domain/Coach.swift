import CoreGraphics
import Foundation

/// AI コーチ（#79）の来訪ロジック（純粋関数）。
///
/// **常駐させない**。いつも部屋にいると存在が空気になり、「来た」ことに意味が無くなる。
/// 用事があるときだけ現れ、対応した（または見送った）ら帰る。
/// 用事の判定は `CharacterChatter` の優先順位をそのまま使う（受け取り待ち > 今日未記録 > 遠征提案）。
enum CoachVisit {

    /// 来訪の理由。`CharacterChatter` が「行動につながる用事」を返したときだけ来る。
    /// 雑談しかないときは来ない。
    enum Topic: String, CaseIterable, Sendable {
        case claim, workout, expedition

        init?(action: CharacterChatter.Line.Action?) {
            switch action {
            case .claim: self = .claim
            case .startWorkout: self = .workout
            case .expedition: self = .expedition
            case nil: return nil
            }
        }
    }

    /// 同じ用事で見送った直後に戻ってこない間隔。
    /// 「今日まだ記録していない」は 1 日じゅう成り立つので、これが無いと結局は常駐になる。
    static let cooldown: TimeInterval = 3 * 60 * 60

    /// いま来訪するか。
    /// 用事が変わったときは（例: 記録の催促 → 遠征の帰還）クールダウン中でもすぐ来る。
    /// 帰還の知らせを 3 時間待たせる理由が無いため。
    static func shouldVisit(
        topic: Topic?,
        lastDismissed: (topic: Topic, at: Date)?,
        now: Date = .now
    ) -> Bool {
        guard let topic else { return false }
        guard let last = lastDismissed else { return true }
        guard last.topic == topic else { return true }
        return now.timeIntervalSince(last.at) >= cooldown
    }

    // MARK: - 出入りの演出

    /// 出入りにかける時間（秒）。歩いて入ってくるので、短すぎると瞬間移動に見える。
    static let transitionDuration: TimeInterval = 1.8

    /// 画面外の待機位置（正規化 x）。ここから歩いて入り、ここへ歩いて帰る。
    static let offstageX: Double = -0.12

    /// 来訪の段階。
    enum Phase: Equatable, Sendable {
        /// 部屋にいない。
        case away
        /// 歩いて入ってくる。
        case arriving
        /// 立っている。
        case present
        /// 歩いて出ていく。
        case leaving
    }

    /// 段階と経過時間から姿勢を作る。`away` と、出ていき終わったあとは nil（描かない）。
    static func pose(phase: Phase, elapsed: TimeInterval, spot: CGPoint) -> CharacterScene.Pose? {
        let t = max(0, elapsed)
        switch phase {
        case .away:
            return nil

        case .arriving, .leaving:
            let progress = CharacterScene.easeInOut(min(1, t / transitionDuration))
            let isArriving = phase == .arriving
            let from = isArriving ? offstageX : Double(spot.x)
            let to = isArriving ? Double(spot.x) : offstageX
            let x = from + (to - from) * progress
            return CharacterScene.Pose(
                position: CGPoint(x: x, y: spot.y),
                facing: isArriving ? .right : .left,
                behavior: .walking,
                walkPhase: (t * CharacterScene.stepsPerSecond).truncatingRemainder(dividingBy: 1),
                emotePhase: 0,
                breathPhase: CharacterScene.breath(at: t),
                blink: 0
            )

        case .present:
            return CharacterScene.Pose(
                position: spot,
                facing: .down,
                behavior: .emoting(.rest),
                walkPhase: 0,
                emotePhase: 0,
                breathPhase: CharacterScene.breath(at: t),
                blink: CharacterScene.blink(at: t, seed: coachBlinkSeed)
            )
        }
    }

    /// まばたきをプレイヤーと揃えないためのシード。
    static let coachBlinkSeed: UInt64 = 0xC0AC_4EED

    /// 出入りのアニメーションが終わったか。
    static func isTransitionFinished(elapsed: TimeInterval) -> Bool {
        elapsed >= transitionDuration
    }
}

/// コーチとの相談（純粋関数）。
///
/// #79 の自由入力チャット（LLM）が入るまでの中身。**選択肢式の会話**として成立させ、
/// 答えは必ず今の記録から導く。答えっぱなしにせず、その場で押せる行動を添える。
enum CoachConsultation {

    /// 相談の 1 項目。ユーザーが `question` を選ぶと `answer` が返る。
    struct Topic: Identifiable, Equatable, Sendable {
        let id: String
        let question: String
        let answer: String
        /// 答えに紐づく行動（無ければ nil）。
        let action: CharacterChatter.Line.Action?
        let actionTitle: String?
    }

    /// いま聞けること。状況によって答えが変わる。
    static func topics(for context: CharacterChatter.Context) -> [Topic] {
        [today(context), condition(context), energy(context), evolution(context)]
    }

    // MARK: - 各項目

    private static func today(_ context: CharacterChatter.Context) -> Topic {
        let remaining = context.weeklyGoal - context.weeklyDone
        let answer: String
        var action: CharacterChatter.Line.Action?
        var actionTitle: String?

        if context.recordedToday {
            answer = "今日はもう動いたね。回復も練習のうちだから、無理に足さなくていい"
        } else if remaining <= 0 {
            answer = "今週の目標はもう達成してる。やりたいなら止めないけど、休んでもいい"
            action = .startWorkout
            actionTitle = "それでもやる"
        } else if remaining == 1 {
            answer = "あと1回で今週の目標。ここで行けると気持ちよく終われる"
            action = .startWorkout
            actionTitle = "記録をはじめる"
        } else {
            answer = "今週はあと\(remaining)回。今日1回やっておくと後が楽になる"
            action = .startWorkout
            actionTitle = "記録をはじめる"
        }
        return Topic(id: "today", question: "今日は何をすればいい？", answer: answer, action: action, actionTitle: actionTitle)
    }

    private static func condition(_ context: CharacterChatter.Context) -> Topic {
        let answer: String
        if context.streakWeeks >= 4 {
            answer = "\(context.streakWeeks)週続いてる。もう習慣になってるよ"
        } else if context.streakWeeks >= 1 {
            answer = "\(context.streakWeeks)週続いてる。いいペースだ"
        } else if let days = context.daysSinceLastWorkout, days >= 7 {
            answer = "\(days)日空いてる。責めはしない。軽い日から戻そう"
        } else if context.daysSinceLastWorkout == nil {
            answer = "まだ記録がないね。まずは1回、軽くていいから残してみて"
        } else {
            answer = "まだ始めたばかり。まずは週\(context.weeklyGoal)回を目標にしよう"
        }
        return Topic(id: "condition", question: "調子はどう？", answer: answer, action: nil, actionTitle: nil)
    }

    private static func energy(_ context: CharacterChatter.Context) -> Topic {
        let answer: String
        var action: CharacterChatter.Line.Action?
        var actionTitle: String?

        switch context.expedition {
        case .awaitingClaim:
            answer = "遠征から戻ってきてる。荷物を開けてあげて"
            action = .claim
            actionTitle = "受け取る"
        case .running(let remaining):
            answer = "いま遠征に出てる。\(remaining)で戻るよ"
        case .idle:
            if let cost = context.cheapestCourseCost, context.energy >= cost {
                answer = "元気が\(context.energy)たまってる。遠征に出せるよ"
                action = .expedition
                actionTitle = "遠征へ"
            } else if let cost = context.cheapestCourseCost {
                answer = "いま元気は\(context.energy)。あと\(max(0, cost - context.energy))で送り出せる。記録すると貯まるよ"
            } else {
                answer = "元気は記録するほど貯まる。レベルが上がると行ける場所が増えるよ"
            }
        }
        return Topic(id: "energy", question: "元気は何に使えるの？", answer: answer, action: action, actionTitle: actionTitle)
    }

    private static func evolution(_ context: CharacterChatter.Context) -> Topic {
        let answer: String
        if context.nextStageUnmet.isEmpty {
            answer = "進化の条件はもう満たしてる。次に記録したときに姿が変わるはず"
        } else {
            answer = "あと\(context.nextStageUnmet.joined(separator: "、"))。焦らなくていい"
        }
        return Topic(id: "evolution", question: "進化まであとどれくらい？", answer: answer, action: nil, actionTitle: nil)
    }
}
