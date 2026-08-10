import Foundation

/// コーチの関わり方（#79 の 3 段階オプション）。
///
/// 「全部決めてほしい人」と「決めてほしくない人」がいる、というのが要望の出発点。
/// **どの段階でも現実の記録がエンジンである点は変わらない**（コーチは決めるだけで、強さは与えない）。
enum CoachMode: String, CaseIterable, Sendable, Identifiable {
    /// 毎朝その日のメニューを確定して提示する。編集はできるが、既定で組み上がっている。
    case auto
    /// ドラフトを出すだけ。確定はユーザーが行う。
    case suggest
    /// コーチは一切現れない（既存体験のまま）。
    case off

    var id: String { rawValue }

    /// 設定に使う保存キー。画面をまたいで参照するのでここに一本化する。
    static let storageKey = "gymnee.coachMode"

    static let `default` = CoachMode.suggest

    var title: String {
        switch self {
        case .auto: return "全部おまかせ"
        case .suggest: return "提案だけ"
        case .off: return "オフ"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "毎朝その日のメニューを決めて出す。重量も休養日も任せる"
        case .suggest: return "案を出すだけ。やるかどうか、内容を変えるかは自分で決める"
        case .off: return "コーチは出てこない。記録だけを使う"
        }
    }

    /// コーチが姿を見せるか。
    var showsCoach: Bool { self != .off }

    /// メニューを確定まで組むか（`suggest` は下書き止まり）。
    var decidesMenu: Bool { self == .auto }

    /// 有料の対象か。決めきってもらう体験だけを課金対象にする
    /// （提案とチャットは無料で触れないと、良さが伝わらないまま終わる）。
    var requiresSubscription: Bool { self == .auto }
}

/// 無料枠の管理（純粋計算）。
///
/// Gemini の呼び出しは 1 往復ごとに費用がかかる。青天井にすると、使われるほど赤字が増える。
/// 「使えない」ではなく「今日はここまで」に留め、翌日また触れるようにする。
enum CoachQuota {

    /// 無料ユーザーが 1 日に送れるメッセージ数。
    static let freeDailyMessages = 10

    /// 有料ユーザーの上限。事実上の無制限だが、暴走時の歯止めとして数値は置く。
    static let paidDailyMessages = 200

    static func limit(isSubscribed: Bool) -> Int {
        isSubscribed ? paidDailyMessages : freeDailyMessages
    }

    /// 今日の残り回数。
    static func remaining(sentToday: Int, isSubscribed: Bool) -> Int {
        max(0, limit(isSubscribed: isSubscribed) - max(0, sentToday))
    }

    static func canSend(sentToday: Int, isSubscribed: Bool) -> Bool {
        remaining(sentToday: sentToday, isSubscribed: isSubscribed) > 0
    }

    /// 上限に達したときの案内。行き止まりにせず、明日また来られることを伝える。
    static func limitMessage(isSubscribed: Bool) -> String {
        isSubscribed
            ? "今日はたくさん話したね。また明日ゆっくり話そう"
            : "今日の相談はここまで。明日また話そう（もっと話したいならプランの見直しもできる）"
    }

    /// 日付が変わったら数え直す。
    static func resetIfNeeded(lastSent: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastSent else { return true }
        return !calendar.isDate(lastSent, inSameDayAs: now)
    }
}
