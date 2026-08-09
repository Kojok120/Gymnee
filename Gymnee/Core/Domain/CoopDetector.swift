import Foundation

/// 合トレ（同じ日に仲間も記録した）の判定。
///
/// 「一緒にジムへ行った」をアプリが知る手段は、同じ日にフォロー中の人の記録が流れてきたかどうか。
/// 位置情報での照合はプライバシー負荷が高く、招待制にすると母数が要る。フィードにすでにある事実だけで
/// 成立させ、成立したら遠征の当たりが出やすくなる（強さは変わらない）。
enum CoopDetector {

    /// その日に記録を上げていたフォロー中の人の名前（重複除去・最大 5 名）。
    /// `feedItems` は自分以外の投稿（フォロー中の人のものだけがローカルに入る）。
    static func partnersToday(
        feedItems: [FeedItem],
        asOf reference: Date = .now,
        calendar: Calendar = .current
    ) -> [String] {
        let day = calendar.startOfDay(for: reference)
        var seen: Set<UUID> = []
        var names: [String] = []
        for item in feedItems where item.type == .workout {
            guard calendar.isDate(calendar.startOfDay(for: item.createdAt), inSameDayAs: day) else { continue }
            guard !seen.contains(item.userId) else { continue }
            seen.insert(item.userId)
            let name = item.authorDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            names.append(name?.isEmpty == false ? name! : "仲間")
            if names.count >= 5 { break }
        }
        return names
    }
}
