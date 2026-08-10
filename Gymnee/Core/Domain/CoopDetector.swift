import Foundation

/// 合トレ（同じ日に仲間も記録した）の判定。
///
/// 「一緒にジムへ行った」をアプリが知る手段は、同じ日にフォロー中の人の記録が流れてきたかどうか。
/// 位置情報での照合はプライバシー負荷が高く、招待制にすると母数が要る。フィードにすでにある事実だけで
/// 成立させ、成立したら遠征の当たりが出やすくなる（強さは変わらない）。
enum CoopDetector {

    /// その日に記録を上げていたフォロー中の人。
    /// 育成シーンに仲間キャラとして並べるため、名前だけでなく本人の id も持つ
    /// （id から見た目を決定的に導出し、同じ人がいつも同じ姿で出るようにする）。
    struct Partner: Identifiable, Equatable, Sendable {
        let id: UUID
        let name: String
    }

    /// その日に記録を上げていたフォロー中の人（重複除去・最大 5 名）。
    /// `feedItems` は自分以外の投稿（フォロー中の人のものだけがローカルに入る）。
    static func partners(
        feedItems: [FeedItem],
        asOf reference: Date = .now,
        calendar: Calendar = .current
    ) -> [Partner] {
        let day = calendar.startOfDay(for: reference)
        var seen: Set<UUID> = []
        var result: [Partner] = []
        for item in feedItems where item.type == .workout {
            guard calendar.isDate(calendar.startOfDay(for: item.createdAt), inSameDayAs: day) else { continue }
            guard !seen.contains(item.userId) else { continue }
            seen.insert(item.userId)
            let name = item.authorDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(Partner(id: item.userId, name: name?.isEmpty == false ? name! : "仲間"))
            if result.count >= 5 { break }
        }
        return result
    }

    /// その日に記録を上げていたフォロー中の人の名前。
    static func partnersToday(
        feedItems: [FeedItem],
        asOf reference: Date = .now,
        calendar: Calendar = .current
    ) -> [String] {
        partners(feedItems: feedItems, asOf: reference, calendar: calendar).map(\.name)
    }
}
