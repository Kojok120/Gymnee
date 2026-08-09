import Foundation

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
    /// 投稿に添えた公開コメント（任意・後方互換）。
    var caption: String? = nil
    /// 投稿写真のストレージ参照（"workout-photos/<uid>/<file>"）。他人の投稿でも表示するため。
    var photoRef: String? = nil
    /// 投稿時点の「今月の活動日数」（カードのチップ。再計算は他人側では不可能なので焼き込む）。
    var monthlyDay: Int? = nil
    /// 投稿時点の育成キャラのレベル（任意・後方互換）。育成の進み具合をソーシャルに乗せるため。
    var characterLevel: Int? = nil
    /// 投稿時点の進化段階の名前（例: チャレンジャー）。
    var characterStage: String? = nil

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

/// フィードに表示する統合エントリ（§6.11）。PR/ワークアウトを 1 つの時系列に束ねる。
/// ローカルでは値型で都度生成（サーバ側フィードは FeedItem モデルで将来差し替え）。
struct FeedEntry: Identifiable {
    enum Kind { case pr, workout }

    let id: UUID
    let date: Date
    let kind: Kind
    let title: String
    let subtitle: String?
    let photoFilename: String?
    /// 公開範囲。投稿コンポーザではセグメントの選択に追従してプレビューを描き替えるため var。
    var visibility: Visibility
    let partners: [String]
    /// 他人の投稿のとき著者の userId（プロフィール遷移用。自分の投稿は nil）。
    var authorId: UUID? = nil
    /// 著者名（自分の投稿にも自分の表示名を入れてカードのヘッダーを他人投稿と揃える）。
    var authorName: String? = nil
    /// 著者アバターの公開URL。
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
    /// 他人の投稿の写真ストレージ参照（"bucket/path"）。SyncedPhoto で取得して表示する。
    var photoRef: String? = nil
    /// 投稿に添えた公開コメント。
    var caption: String? = nil
    /// 「今月○日目」チップ。nil なら非表示。
    var monthlyDay: Int? = nil

    /// 投稿時点の育成キャラ（「Lv.12 チャレンジャー」チップ）。nil なら非表示。
    var characterLevel: Int? = nil
    var characterStage: String? = nil

    /// 他ユーザーの投稿か（メニュー・写真取得経路などの分岐用）。
    /// 自分の投稿にも authorName を入れるため「名前の有無」からは導出せず明示フラグで持つ。
    var isFromOther: Bool = false

    /// 公開済み（feed_item が存在する）か。他人の投稿は常に true。
    /// 自分の未公開記録（feed_item 無し）では応援/コメントを出さない（親不在の post_reactions/comments が
    /// FK 違反で滞留・孤児化するのを防ぐ）。表示は「非公開」バッジ付きのカードのみ。
    var isPublished: Bool = true

    /// feed_item の種別（公開範囲変更で FeedPublisher に渡す）。
    var feedItemType: FeedItemType {
        switch kind {
        case .pr: return .pr
        case .workout: return .workout
        }
    }

    var icon: String {
        switch kind {
        case .pr: return "trophy.fill"
        case .workout: return "dumbbell.fill"
        }
    }
}

enum FeedBuilder {
    /// PR・完了ワークアウトを統合し、新しい順に並べる。
    /// 公開範囲は自分の feed_items 由来（`publishedVisibilityById`）。feed_item が無い記録は
    /// 未公開＝`.private` 表示（自分だけに見える。フォロワーには出ない）。
    /// ownerName/ownerAvatarURL を渡すと自分の投稿カードにも名前・アバターを表示できる。
    static func build(
        personalRecords: [PersonalRecord],
        workouts: [Workout],
        publishedVisibilityById: [UUID: Visibility],
        ownerName: String? = nil,
        ownerAvatarURL: String? = nil,
        calendar: Calendar = .current
    ) -> [FeedEntry] {
        var entries: [FeedEntry] = []
        func vis(_ id: UUID) -> Visibility { publishedVisibilityById[id] ?? .private }
        func published(_ id: UUID) -> Bool { publishedVisibilityById[id] != nil }
        // ワークアウトごとの PR 件数を先に索引化（workout×PR の全走査を避ける。FeedPublisher と同じ手法）。
        var prCountByWorkout: [UUID: Int] = [:]
        for pr in personalRecords { if let wid = pr.workoutId { prCountByWorkout[wid, default: 0] += 1 } }
        // 「今月○日目」は各ワークアウトの日付時点で数える（過去の投稿を遡って見ても値が変わらない）。
        let activeDays = workouts.filter { $0.completedAt != nil }.map { $0.completedAt ?? $0.date }

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
                authorName: ownerName,
                authorAvatarURL: ownerAvatarURL,
                prKind: pr.type,
                isPublished: published(pr.id)
            ))
        }

        for w in workouts where w.completedAt != nil {
            entries.append(workoutEntry(
                w,
                prCount: prCountByWorkout[w.id] ?? 0,
                activeDays: activeDays,
                visibility: vis(w.id),
                isPublished: published(w.id),
                ownerName: ownerName,
                ownerAvatarURL: ownerAvatarURL,
                calendar: calendar
            ))
        }

        return entries.sorted { $0.date > $1.date }
    }

    /// 完了ワークアウト 1 件をフィード項目にする。
    /// フィード一覧と投稿コンポーザのプレビューで**同じ関数**を使い、
    /// 「プレビューと実際の投稿が食い違う」余地を作らない。
    static func workoutEntry(
        _ w: Workout,
        prCount: Int,
        activeDays: [Date],
        visibility: Visibility,
        isPublished: Bool,
        ownerName: String? = nil,
        ownerAvatarURL: String? = nil,
        character: (level: Int, stage: String)? = nil,
        calendar: Calendar = .current
    ) -> FeedEntry {
        let sets = w.exercises.flatMap(\.sets)
        let vol = sets.reduce(0.0) { $0 + $1.volume }
        let totalVolume = vol.isFinite ? Int(vol) : 0
        // 鍛えた部位（重複除去・元の並び維持）。
        var seenMuscle = Set<MuscleGroup>()
        let muscles = w.exercises.compactMap { $0.exercise?.muscleGroup }.filter { seenMuscle.insert($0).inserted }

        // 「種目」件数は詳細(メニュー)と一致させる（セットの無い空種目は数えない）。
        let visibleExercises = w.exercises.filter { !$0.sets.isEmpty }
        // カードのチップは「時間」「今月○日目」を主役にするため、時間を先頭に置く。
        var stats: [FeedStat] = []
        if let mins = WorkoutDuration.minutes(date: w.date, completedAt: w.completedAt, durationSeconds: w.durationSeconds) {
            stats.append(FeedStat(label: "時間", value: "\(mins)分"))
        }
        stats.append(FeedStat(label: "セット", value: "\(sets.count)"))
        if totalVolume > 0 { stats.append(FeedStat(label: "ボリューム", value: "\(totalVolume) kg")) }

        // 共有画像は「種目名＋全セット」を並べる（ベスト重量×合計セット数の要約は不正確なので使わない）。
        let lines = visibleExercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { we in
                FeedItemStats.ExerciseLine(
                    name: we.exercise?.name ?? "種目",
                    sets: we.sets.sorted { $0.setIndex < $1.setIndex }
                        .map { FeedItemStats.SetLine(text: $0.detailText, isPR: $0.isPR) }
                )
            }

        return FeedEntry(
            id: w.id,
            date: w.date,
            kind: .workout,
            title: w.name,
            subtitle: nil,
            photoFilename: w.localPhotoFilename,
            visibility: visibility,
            partners: [],
            authorName: ownerName,
            authorAvatarURL: ownerAvatarURL,
            stats: stats,
            muscles: muscles,
            prCount: prCount,
            workoutLines: lines,
            caption: w.caption,
            monthlyDay: StreakCalculator.monthlyActiveDays(
                activeDays: activeDays, in: w.completedAt ?? w.date, calendar: calendar
            ),
            characterLevel: character?.level,
            characterStage: character?.stage,
            isPublished: isPublished
        )
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
            // 旧チェックイン投稿（type='visit'）は取り込み時に捨てているが、
            // 取りこぼしがあっても描けないので念のためここでも弾く。
            guard item.typeRaw != FeedItemType.legacyVisitRawValue else { return nil }
            let kind: FeedEntry.Kind
            switch item.type {
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
                authorId: item.userId,
                authorName: profile?.displayName ?? item.authorDisplayName ?? "ユーザー",
                authorAvatarURL: profile?.avatarURL,
                stats: stats?.feedStats ?? [],
                muscles: stats?.muscleGroups ?? [],
                prCount: stats?.prCount ?? 0,
                workoutLines: stats?.exerciseLines,
                photoRef: stats?.photoRef,
                caption: stats?.caption,
                monthlyDay: stats?.monthlyDay,
                characterLevel: stats?.characterLevel,
                characterStage: stats?.characterStage,
                isFromOther: true
            )
        }
    }

    private static func formatPR(_ pr: PersonalRecord) -> String {
        pr.type.formatted(pr.value)
    }
}
