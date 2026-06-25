import Foundation
import Observation

/// 投稿ごとの公開範囲（端末ローカル保存）。
/// 現状マルチユーザー共有は未稼働のため visibility は実効しないが、UI 上で投稿単位に
/// 設定・表示できるようにする。共有実装時に各レコード列（visits/workouts.visibility）へ移行する。
@Observable
final class PostVisibilityStore {
    private let key = "gymnee.postVisibility"
    private var map: [String: String]

    init() {
        map = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    func visibility(for id: UUID) -> Visibility? {
        map[id.uuidString].flatMap { Visibility(rawValue: $0) }
    }

    func set(_ visibility: Visibility, for id: UUID) {
        map[id.uuidString] = visibility.rawValue
        UserDefaults.standard.set(map, forKey: key)
    }
}

/// フィードに表示する統合エントリ（§6.11）。来店/PR/ワークアウトを 1 つの時系列に束ねる。
/// ローカルでは値型で都度生成（サーバ側フィードは FeedItem モデルで将来差し替え）。
struct FeedEntry: Identifiable {
    enum Kind { case visit, pr, workout }

    let id: UUID
    let date: Date
    let kind: Kind
    let title: String
    let subtitle: String?
    let photoFilename: String?
    let visibility: Visibility
    let partners: [String]
    /// 他人の投稿のとき著者名（自分の投稿は nil）。
    var authorName: String? = nil
    /// 他人の投稿のとき著者アバターの公開URL。
    var authorAvatarURL: String? = nil

    /// 他ユーザーの投稿か（フィード上の表示分岐用）。
    var isFromOther: Bool { authorName != nil }

    var icon: String {
        switch kind {
        case .visit: return "camera.fill"
        case .pr: return "trophy.fill"
        case .workout: return "dumbbell.fill"
        }
    }
}

enum FeedBuilder {
    /// 来店・PR・完了ワークアウトを統合し、新しい順に並べる。
    static func build(
        visits: [Visit],
        personalRecords: [PersonalRecord],
        workouts: [Workout],
        defaultVisibility: Visibility,
        visibilityStore: PostVisibilityStore? = nil
    ) -> [FeedEntry] {
        var entries: [FeedEntry] = []
        func vis(_ id: UUID) -> Visibility { visibilityStore?.visibility(for: id) ?? defaultVisibility }

        for v in visits {
            entries.append(FeedEntry(
                id: v.id,
                date: v.visitedAt,
                kind: .visit,
                title: v.gym?.name ?? "チェックイン",
                subtitle: v.note,
                photoFilename: v.localPhotoFilename,
                visibility: vis(v.id),
                partners: v.partners.compactMap(\.partnerDisplayName)
            ))
        }

        for pr in personalRecords {
            let valueText = formatPR(pr)
            entries.append(FeedEntry(
                id: pr.id,
                date: pr.achievedAt,
                kind: .pr,
                title: "\(pr.exercise?.name ?? "種目") \(pr.type.label)",
                subtitle: valueText,
                photoFilename: nil,
                visibility: vis(pr.id),
                partners: []
            ))
        }

        for w in workouts where w.completedAt != nil {
            let totalSets = w.exercises.reduce(0) { $0 + $1.sets.count }
            entries.append(FeedEntry(
                id: w.id,
                date: w.date,
                kind: .workout,
                title: w.name,
                subtitle: "\(w.exercises.count)種目・\(totalSets)セット",
                photoFilename: nil,
                visibility: vis(w.id),
                partners: []
            ))
        }

        return entries.sorted { $0.date > $1.date }
    }

    /// フォロー中の他ユーザーの投稿（サーバーから取り込んだ feed_items）をフィード項目へ変換する。
    /// 著者名・アバターはローカルに保持している Profile から引く。
    static func othersEntries(
        feedItems: [FeedItem],
        excludingUser userId: UUID,
        profilesById: [UUID: Profile]
    ) -> [FeedEntry] {
        feedItems.compactMap { item -> FeedEntry? in
            guard item.userId != userId else { return nil }
            let kind: FeedEntry.Kind
            switch item.type {
            case .visit: kind = .visit
            case .pr: kind = .pr
            case .workout: kind = .workout
            }
            let profile = profilesById[item.userId]
            return FeedEntry(
                id: item.id,
                date: item.createdAt,
                kind: kind,
                title: item.summary ?? "投稿",
                subtitle: nil,
                photoFilename: nil,
                visibility: item.visibility,
                partners: [],
                authorName: profile?.displayName ?? item.authorDisplayName ?? "ユーザー",
                authorAvatarURL: profile?.avatarURL
            )
        }
    }

    private static func formatPR(_ pr: PersonalRecord) -> String {
        pr.type.formatted(pr.value)
    }
}
