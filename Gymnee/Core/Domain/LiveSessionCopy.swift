import Foundation

/// 「いまトレーニング中」と応援の見せ方（純粋計算）。
///
/// スタンプの語彙は `post_reactions` と揃える。投稿へのリアクションと応援で
/// 別の記号を使うと、同じ気持ちを表すのに 2 通り覚えることになる。
enum LiveSessionCopy {

    /// 応援に使えるスタンプ。like は投稿向けなので、応援では熱量のある 3 つに絞る。
    static let cheerKinds = ["fire", "clap", "strong"]

    static func emoji(_ kind: String) -> String {
        switch kind {
        case "fire": return "🔥"
        case "strong": return "💪"
        case "clap": return "👏"
        default: return "❤️"
        }
    }

    static func label(_ kind: String) -> String {
        switch kind {
        case "fire": return "ファイト"
        case "strong": return "つよい"
        case "clap": return "拍手"
        default: return "いいね"
        }
    }

    /// 経過時間の一言。**分単位までで十分**（秒を出すと監視されている感じが出る）。
    /// 生きているとみなす上限（3時間）を超えたぶんは出さない。
    static func elapsed(from start: Date, now: Date = .now) -> String {
        let minutes = Int(now.timeIntervalSince(start) / 60)
        guard minutes >= 1 else { return "始めたところ" }
        guard minutes < 60 else {
            let extra = minutes % 60
            return extra > 0 ? "\(minutes / 60)時間\(extra)分経過" : "\(minutes / 60)時間経過"
        }
        return "\(minutes)分経過"
    }

    /// 生きているとみなす上限。サーバ（`live_session_max_duration`）と揃える。
    /// ここを長くすると、終了し損ねたセッションを延々と応援させることになる。
    static let maxDuration: TimeInterval = 3 * 60 * 60

    static func isLive(startedAt: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(startedAt) < maxDuration
    }
}
