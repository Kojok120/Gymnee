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
        case .auto: return "毎朝その日のメニューを決めて出します。重量も休養日も任せられます"
        case .suggest: return "案を出すだけです。やるかどうか、内容を変えるかは自分で決められます"
        case .off: return "コーチは出てきません。記録だけを使います"
        }
    }

    /// コーチが姿を見せるか。
    var showsCoach: Bool { self != .off }

    /// メニューを確定まで組むか（`suggest` は下書き止まり）。
    var decidesMenu: Bool { self == .auto }
}

/// 相談回数の上限（純粋計算）。
///
/// Gemini の呼び出しは 1 往復ごとに費用がかかる。青天井にすると、使われるほど赤字が増える。
/// 「使えない」ではなく「今日はここまで」に留め、翌日また触れるようにする。
///
/// **これはコスト制御であって課金の話ではない**。アプリ内課金は見た目（スキン / 髪型 /
/// アクセサリー / ペット）だけで、サブスクリプションは提供していないので、
/// 上限をプランで出し分けることはしない。
enum CoachQuota {

    /// 1 日に送れるメッセージ数。
    static let dailyMessages = 10

    /// 今日の残り回数。
    static func remaining(sentToday: Int) -> Int {
        max(0, dailyMessages - max(0, sentToday))
    }

    static func canSend(sentToday: Int) -> Bool {
        remaining(sentToday: sentToday) > 0
    }

    /// 上限に達したときの案内。行き止まりにせず、明日また来られることを伝える。
    static let limitMessage = "今日の相談はここまで。明日また話そう"

    /// 日付が変わったら数え直す。
    static func resetIfNeeded(lastSent: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastSent else { return true }
        return !calendar.isDate(lastSent, inSameDayAs: now)
    }
}
