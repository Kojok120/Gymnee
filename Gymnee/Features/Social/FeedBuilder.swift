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
    /// 種目別のセット内訳（他人の投稿でも「メニュー」を再現するため。任意・後方互換）。
    var exerciseLines: [ExerciseLine]? = nil

    /// 1 種目分のセット内訳。
    struct ExerciseLine: Codable, Equatable {
        var name: String
        var sets: [SetLine]
    }
    /// 1 セット分（表示テキスト＋PR フラグ）。
    struct SetLine: Codable, Equatable {
        var text: String
        var isPR: Bool
    }

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

/// feed_items.stats_json に載せる来店投稿のメタ（写真ストレージ参照）。
/// 他人の投稿でも来店写真を表示するため、本人の visit.photoURL（"bucket/path"）を載せる。
struct FeedItemVisitStats: Codable {
    var photoRef: String?

    func encodedJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func decode(_ json: String?) -> FeedItemVisitStats? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FeedItemVisitStats.self, from: data)
    }
}

/// ソーシャル行描画用の名前/アバター索引。行ごとの profiles/comments 線形走査（O(行数×全件)）を
/// 避けるため、body 評価ごとに 1 回だけ構築して行ビルダーへ配る（PostDetailView / SocialActivityView）。
struct SocialNameIndex {
    private let profileById: [UUID: Profile]
    private let commentNameById: [UUID: String]

    init(profiles: [Profile], comments: [Comment] = []) {
        profileById = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // コメントの非正規化著者名（プロフィール未同期の相手の安全網）。ユーザーごと最初の非空値。
        var byUser: [UUID: String] = [:]
        for c in comments where byUser[c.userId] == nil {
            if let n = c.authorDisplayName, !n.isEmpty { byUser[c.userId] = n }
        }
        commentNameById = byUser
    }

    /// プロフィール表示名 → コメント著者名 → fallback → 「ユーザー」の順で解決する。
    func name(_ id: UUID?, fallback: String? = nil) -> String {
        guard let id else { return "ユーザー" }
        if let n = profileById[id]?.displayName, !n.isEmpty { return n }
        if let n = commentNameById[id] { return n }
        if let f = fallback, !f.isEmpty { return f }
        return "ユーザー"
    }

    func avatarURL(_ id: UUID) -> String? { profileById[id]?.avatarURL }
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
    /// 他人の投稿のとき著者の userId（プロフィール遷移用。自分の投稿は nil）。
    var authorId: UUID? = nil
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
    /// 他人のワークアウト投稿の種目別セット内訳（feed の statsJSON から復元。自分の投稿はローカル実体から描く）。
    var workoutLines: [FeedItemStats.ExerciseLine]? = nil
    /// 他人の来店投稿の写真ストレージ参照（"bucket/path"）。SyncedPhoto で取得して表示する。
    var photoRef: String? = nil

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
        // ワークアウトごとの PR 件数を先に索引化（workout×PR の全走査を避ける。FeedPublisher と同じ手法）。
        var prCountByWorkout: [UUID: Int] = [:]
        for pr in personalRecords { if let wid = pr.workoutId { prCountByWorkout[wid, default: 0] += 1 } }

        for v in visits {
            entries.append(FeedEntry(
                id: v.id,
                date: v.visitedAt,
                kind: .visit,
                title: v.gym?.name ?? "ジム活",
                subtitle: v.note,
                photoFilename: v.localPhotoFilename,
                visibility: vis(v.id),
                partners: v.partners.compactMap(\.partnerDisplayName)
            ))
        }

        // 自己ベスト投稿は「最大重量」のみ。推定1RM/最大レップ/最長時間などその他のトロフィーは
        // 単独投稿にせず、ワークアウト記録（各セットのトロフィー表示）に内包する。
        // 発行側（FeedPublisher）と表示基準を揃え、自分の投稿一覧とフォロワーのフィードを一致させる。
        for pr in personalRecords where pr.type == .maxWeight {
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
            let prCount = prCountByWorkout[w.id] ?? 0
            // 鍛えた部位（重複除去・元の並び維持）。
            var seenMuscle = Set<MuscleGroup>()
            let muscles = w.exercises.compactMap { $0.exercise?.muscleGroup }.filter { seenMuscle.insert($0).inserted }

            // 「種目」件数は詳細(メニュー)と一致させる（セットの無い空種目は数えない）。
            let exerciseCount = w.exercises.filter { !$0.sets.isEmpty }.count
            var stats: [FeedStat] = [
                FeedStat(label: "種目", value: "\(exerciseCount)"),
                FeedStat(label: "セット", value: "\(totalSets)"),
            ]
            if totalVolume > 0 { stats.append(FeedStat(label: "ボリューム", value: "\(totalVolume) kg")) }
            if let mins = WorkoutDuration.minutes(date: w.date, completedAt: w.completedAt, durationSeconds: w.durationSeconds) {
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
            // 来店投稿は statsJSON に写真参照を載せている（ワークアウトの statsJSON とは別形式）。
            let visitPhotoRef = kind == .visit ? FeedItemVisitStats.decode(item.statsJSON)?.photoRef : nil
            return FeedEntry(
                id: item.id,
                date: item.createdAt,
                kind: kind,
                title: item.summary ?? "投稿",
                subtitle: nil,
                photoFilename: nil,
                visibility: item.visibility,
                partners: [],
                authorId: item.userId,
                authorName: profile?.displayName ?? item.authorDisplayName ?? "ユーザー",
                authorAvatarURL: profile?.avatarURL,
                stats: stats?.feedStats ?? [],
                muscles: stats?.muscleGroups ?? [],
                prCount: stats?.prCount ?? 0,
                workoutLines: stats?.exerciseLines,
                photoRef: visitPhotoRef
            )
        }
    }

    private static func formatPR(_ pr: PersonalRecord) -> String {
        pr.type.formatted(pr.value)
    }
}
