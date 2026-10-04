import Foundation

/// 育成タブを開いた直後に出す案内の順番（issue #120）。
///
/// 初回のワークアウト完了 → 育成タブ、という新規ユーザーの典型的な流れでは、
/// 「成長祝い」と「遊び方の説明」が同じタイミングで立つ。SwiftUI は同時に1枚しか
/// シートを出せないため、片方が落ちていた。成長祝いの控えは取り出した時点で消えるので、
/// 落ちた祝いは戻らず、祝いの後に出す通知の確認も出なかった。
/// 1枚ずつ順番に出す: 祝い → 遊び方 → 通知の確認。
enum RoomIntro {
    enum Step: Equatable, Sendable {
        case celebration
        case onboarding
        /// 通知の許諾確認。記録の価値を見せた（祝いを出した）後にだけ尋ねる
        /// （EXP-20260818-notification-permission-after-workout）。
        case notificationPrompt
    }

    /// 今回出す案内を、出す順に並べる。
    static func steps(hasCelebration: Bool, needsOnboarding: Bool) -> [Step] {
        var steps: [Step] = []
        if hasCelebration { steps.append(.celebration) }
        if needsOnboarding { steps.append(.onboarding) }
        if hasCelebration { steps.append(.notificationPrompt) }
        return steps
    }

    /// 案内の待ち行列に今回の分を足す。同じ種類は重ねない（呼び出し元が複数のきっかけ
    /// から何度も呼ぶため）。足した結果、元の行列の後ろに並ぶ。
    static func enqueue(_ new: [Step], into queue: [Step]) -> [Step] {
        var result = queue
        for step in new where !result.contains(step) {
            result.append(step)
        }
        // 通知の確認は常に最後（遊び方の説明より先に尋ねない）。
        if let i = result.firstIndex(of: .notificationPrompt), i != result.count - 1 {
            result.remove(at: i)
            result.append(.notificationPrompt)
        }
        return result
    }
}
