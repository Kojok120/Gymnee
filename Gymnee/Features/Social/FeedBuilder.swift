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

/// フィードカードに自動ハイライトする 1 メトリクス（⑦）。
struct FeedStat: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

/// feed_items.stats_json に載せる構造化スタッツ（ワークアウト投稿・⑦E）。
/// フォロワー側でも復元してリッチカードを描くため、サマリ文字列ではなく数値で持つ。
struct FeedItemStats: Codable {
    var exercises: Int
    var sets: Int
    var volume: Int
    var minutes: Int?
    var prCount: Int
    var muscles: [String]   // MuscleGroup.rawValue

    func encodedJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func decode(_ json: String?) -> FeedItemStats? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FeedItemStats.self, from: data)
    }
    /// カード表示用のチップ配列。
    var feedStats: [FeedStat] {
        var s: [FeedStat] = [FeedStat(label: "種目", value: "\(exercises)"), FeedStat(label: "セット", value: "\(sets)")]
        if volume > 0 { s.append(FeedStat(label: "ボリューム", value: "\(volume) kg")) }
        if let m = minutes { s.append(FeedStat(label: "時間", value: "\(m)分")) }
        return s
    }
    var muscleGroups: [MuscleGroup] { muscles.compactMap { MuscleGroup(rawValue: $0) } }
}

/// feed_items.stats_json に載せる自己ベスト投稿のスタッツ（PR投稿）。
/// フォロワー側でも種目名＋計測タイプ別の数値を復元して一覧表示するため、サマリ文字列ではなく数値で持つ。
/// （feed_items の stats_json 列は既存なのでスキーマ変更は不要。改修後に発行された PR から数値が載る）
struct FeedItemPRStats: Codable {
    struct Item: Codable {
        var type: String   // PRType.rawValue
        var value: Double
    }
    var exercise: String
    var items: [Item]

    func encodedJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func decode(_ json: String?) -> FeedItemPRStats? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FeedItemPRStats.self, from: data)
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
    /// 自動ハイライトする主要スタッツ（種目/セット/ボリューム/時間など）。ワークアウト投稿で使う。
    var stats: [FeedStat] = []
    /// このワークアウトが鍛えた部位（カードのドット表示）。
    var muscles: [MuscleGroup] = []
    /// このワークアウトで更新した PR 件数（>0 ならカードに金バッジ）。
    var prCount: Int = 0
    /// PR 投稿の計測タイプ（トロフィーのアイコン/ラベル）。
    var prKind: PRType? = nil

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
                partners: [],
                prKind: pr.type
            ))
        }

        for w in workouts where w.completedAt != nil {
            let sets = w.exercises.flatMap(\.sets)
            let totalSets = sets.count
            let vol = sets.reduce(0.0) { $0 + $1.volume }
            let totalVolume = vol.isFinite ? Int(vol) : 0
            let prCount = personalRecords.filter { $0.workoutId == w.id }.count
            // 鍛えた部位（重複除去・元の並び維持）。
            var seenMuscle = Set<MuscleGroup>()
            let muscles = w.exercises.compactMap { $0.exercise?.muscleGroup }.filter { seenMuscle.insert($0).inserted }

            var stats: [FeedStat] = [
                FeedStat(label: "種目", value: "\(w.exercises.count)"),
                FeedStat(label: "セット", value: "\(totalSets)"),
            ]
            if totalVolume > 0 { stats.append(FeedStat(label: "ボリューム", value: "\(totalVolume) kg")) }
            if let end = w.completedAt {
                let mins = max(1, Int(end.timeIntervalSince(w.date) / 60))
                stats.append(FeedStat(label: "時間", value: "\(mins)分"))
            }

            entries.append(FeedEntry(
                id: w.id,
                date: w.date,
                kind: .workout,
                title: w.name,
                subtitle: nil,
                photoFilename: nil,
                visibility: vis(w.id),
                partners: [],
                stats: stats,
                muscles: muscles,
                prCount: prCount
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
            let stats = FeedItemStats.decode(item.statsJSON)
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
                authorAvatarURL: profile?.avatarURL,
                stats: stats?.feedStats ?? [],
                muscles: stats?.muscleGroups ?? [],
                prCount: stats?.prCount ?? 0
            )
        }
    }

    private static func formatPR(_ pr: PersonalRecord) -> String {
        pr.type.formatted(pr.value)
    }
}
