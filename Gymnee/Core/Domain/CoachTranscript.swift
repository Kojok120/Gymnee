import Foundation

/// コーチとの会話のうち、開いたときに見せるぶんの切り分け。
///
/// 会話は消さずに残すが、**開くたびに過去の壁を見せない**。
/// コーチは「今日どうするか」の相談相手なので、既定は今日ぶんだけを開き、
/// それ以前はユーザーが明示的に遡ったときにだけ見せる。
///
/// AI に渡す文脈は直近 12 通だけ（`CoachService.wireHistory`）で、
/// それより古い会話は返答の質に一切寄与しない。貯めたものを見せ続ける理由は無い。
enum CoachTranscript {

    /// 「今日より前」と「今日」に割った結果。
    struct Split<Message> {
        /// 今日より前の会話（既定では畳む）。
        var past: [Message]
        /// 今日の会話（既定で開く）。
        var today: [Message]
    }

    /// 時系列昇順の会話を、その日の始まりを境に割る。
    /// 境界は暦の「今日の 0 時」。日付が変わったら前日ぶんは past に落ちる。
    static func split<Message>(
        _ messages: [Message],
        now: Date = .now,
        calendar: Calendar = .current,
        date: (Message) -> Date
    ) -> Split<Message> {
        let startOfToday = calendar.startOfDay(for: now)
        var past: [Message] = []
        var today: [Message] = []
        for message in messages {
            if date(message) < startOfToday {
                past.append(message)
            } else {
                today.append(message)
            }
        }
        return Split(past: past, today: today)
    }
}
