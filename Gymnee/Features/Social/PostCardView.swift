import SwiftUI

/// 投稿カードの描画（アプリ内フィード ＋ SNS 共有画像で共通）。
///
/// **意匠は 1 つ、情報密度だけ媒体に合わせる**という設計:
/// - `.feed`  アプリ内。写真が主役で、種目は 1 行の要約。詳細はタップで `WorkoutDetailView` へ飛ばせる。
/// - `.share` SNS へ出す画像。タップできない媒体なので、種目ごとに**全セットをそのまま並べる**。
///
/// 種目行を「ベスト重量 × 合計セット数」に要約すると *ベスト重量を全セットやった* と読めて不正確なため、
/// 記録画面・完了サマリーと同じ `ExerciseSet.detailText` を 1 セット 1 要素で並べる。
/// 溢れる場合は**種目単位**で畳む（セット単位で削ると同じ不正確さが再発する）。
struct PostCardView: View {
    let entry: FeedEntry
    var style: PostCardStyle = .feed
    /// `.share` の基準幅（ImageRenderer 用）。`.feed` では無視される。
    var side: CGFloat = 360

    /// 自分の投稿写真。初回スクロール時の同期ディスク I/O ＋フル解像度デコードが
    /// メインスレッドを塞がないよう非同期に読み込む（2回目以降は NSCache 命中で即時）。
    @State private var ownPhoto: UIImage?
    @State private var ownPhotoMissing = false

    /// `.share` は ImageRenderer 上で描くため非同期ロードが走らない。呼び出し側が同期で読んで渡す。
    var preloadedPhoto: UIImage?

    private var metrics: PostCardMetrics {
        style == .share ? .share(side: side) : .feed
    }
    private var isPRHighlight: Bool { entry.kind == .pr || entry.prCount > 0 }

    var body: some View {
        switch style {
        case .feed:
            content.gymneeCard(highlighted: isPRHighlight)
        case .share:
            content
                .padding(metrics.padding)
                .frame(width: side, alignment: .leading)
                .background(Theme.bg1)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: metrics.spacing) {
            header
            if !entry.stats.isEmpty || entry.monthlyDay != nil || entry.characterLevel != nil { chipRow }
            if entry.kind == .pr { prBody }
            photo
            if let caption = entry.caption, !caption.isEmpty {
                Text(caption)
                    .font(metrics.caption)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            exercises
            if !entry.muscles.isEmpty, style == .feed { muscleRow }
        }
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(spacing: metrics.spacing * 0.6) {
            AvatarView(urlString: entry.authorAvatarURL, size: metrics.avatarSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.authorName ?? "自分").font(metrics.authorName).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(entry.date, format: .dateTime.month().day().hour().minute())
                    .font(metrics.meta).foregroundStyle(.secondary)
            }
            Spacer(minLength: metrics.spacing)
            switch style {
            case .feed:
                Label(entry.visibility.label, systemImage: visibilityIcon)
                    .font(metrics.meta).foregroundStyle(.secondary)
                    .lineLimit(1).layoutPriority(1)
            case .share:
                // 共有画像は出所がわかるようブランドを焼き込む（公開範囲ラベルは意味がない）。
                Label("Gymnee", systemImage: "figure.strengthtraining.traditional")
                    .font(metrics.brand).foregroundStyle(Theme.lime)
                    .lineLimit(1).layoutPriority(1)
            }
        }
    }

    private var visibilityIcon: String {
        switch entry.visibility {
        case .private: return "lock.fill"
        case .friends: return "person.2.fill"
        case .public: return "globe"
        }
    }

    // MARK: - チップ（時間 / 今月○日目 / PR）

    /// スケッチの「時間○分」「今月○日目」を主役に、他のスタッツは補助として続ける。
    private var chipRow: some View {
        HStack(spacing: metrics.spacing * 0.5) {
            if entry.prCount > 0 { prBadge }
            if let level = entry.characterLevel {
                chip(label: entry.characterStage ?? "育成", value: "Lv.\(level)")
            }
            if let day = entry.monthlyDay, day > 0 {
                chip(label: "今月", value: "\(day)日目")
            }
            ForEach(entry.stats) { chip(label: $0.label, value: $0.value) }
        }
    }

    private var prBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "trophy.fill")
            Text("PR \(entry.prCount)")
        }
        .font(metrics.chipLabel.bold())
        .foregroundStyle(Theme.onLime)
        .padding(.horizontal, metrics.padding * 0.4)
        .padding(.vertical, metrics.padding * 0.25)
        .background(Theme.limeFill, in: Capsule())
    }

    private func chip(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(metrics.chipValue).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(metrics.chipLabel).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.padding * 0.35)
        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
    }

    // MARK: - 写真

    @ViewBuilder private var photo: some View {
        if let preloadedPhoto {
            photoFrame { Image(uiImage: preloadedPhoto).resizable().scaledToFill() }
        } else if style == .share {
            // ImageRenderer 上では .task も非同期ロードも走らないため、渡されなかった時は
            // 空のプレースホルダ枠を焼き込まず写真ごと省く（灰色の箱が写った画像を共有させない）。
            EmptyView()
        } else if entry.photoFilename != nil && !ownPhotoMissing {
            photoFrame {
                if let ownPhoto {
                    Image(uiImage: ownPhoto).resizable().scaledToFill()
                } else {
                    Theme.bg2   // 読込中プレースホルダ（高さを固定してレイアウト跳ねを防ぐ）
                }
            }
            .task(id: entry.photoFilename) {
                let filename = entry.photoFilename
                let image = await Task.detached(priority: .userInitiated) { PhotoStore.load(filename) }.value
                ownPhoto = image
                ownPhotoMissing = (image == nil)
            }
        } else if let ref = entry.photoRef, !ref.isEmpty {
            // 他人の投稿写真：ストレージ参照から取得（権限が無ければプレースホルダのまま）。
            photoFrame { SyncedPhoto(filename: nil, ref: ref) { Color.clear }.scaledToFill() }
        }
    }

    private func photoFrame<V: View>(@ViewBuilder _ image: () -> V) -> some View {
        image()
            .frame(maxWidth: .infinity).frame(height: metrics.photoHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius))
    }

    // MARK: - 種目

    @ViewBuilder private var exercises: some View {
        switch style {
        case .feed:
            if let summary = feedExerciseSummary {
                Text(summary).font(metrics.meta).foregroundStyle(.secondary).lineLimit(1)
            }
        case .share:
            if let lines = entry.workoutLines, !lines.isEmpty { shareExerciseList(lines) }
        }
    }

    /// `.feed` の 1 行要約（例「胸・三頭 5種目」）。詳細はタップ先の画面に任せる。
    private var feedExerciseSummary: String? {
        guard entry.kind == .workout else { return nil }
        let count = entry.workoutLines?.count ?? 0
        guard count > 0 else { return nil }
        let muscles = entry.muscles.prefix(2).map(\.label).joined(separator: "・")
        return muscles.isEmpty ? "\(count)種目" : "\(muscles) \(count)種目"
    }

    /// `.share` の種目一覧。1 種目 = 名前 ＋ 全セットを `" / "` で連結（完了サマリーと同じ表記）。
    private func shareExerciseList(_ lines: [FeedItemStats.ExerciseLine]) -> some View {
        let shown = Array(lines.prefix(PostCardView.shareMaxExercises))
        return VStack(alignment: .leading, spacing: metrics.spacing * 0.45) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(line.name).font(metrics.exerciseName).foregroundStyle(Theme.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if line.sets.contains(where: \.isPR) {
                            Image(systemName: "trophy.fill").font(metrics.chipLabel).foregroundStyle(Theme.lime)
                        }
                    }
                    Text(setsText(line.sets))
                        .font(metrics.setText).foregroundStyle(.secondary)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
            }
            if lines.count > shown.count {
                Text("＋他\(lines.count - shown.count)種目")
                    .font(metrics.setText).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// 全セットを並べる。極端にセット数が多いときだけ「…他Nセット」と明示する
    /// （重量を丸めず、やっていないセットを増やさないための上限）。
    private func setsText(_ sets: [FeedItemStats.SetLine]) -> String {
        let shown = sets.prefix(PostCardView.shareMaxSetsPerExercise)
        var text = shown.map(\.text).joined(separator: " / ")
        if sets.count > shown.count { text += " …他\(sets.count - shown.count)セット" }
        return text
    }

    /// 共有画像に載せる種目数の上限（超過分は種目単位で畳む）。
    static let shareMaxExercises = 8
    /// 1 種目あたりに並べるセット数の上限。
    static let shareMaxSetsPerExercise = 8

    // MARK: - その他

    private var muscleRow: some View {
        HStack(spacing: 5) {
            ForEach(entry.muscles.prefix(8), id: \.self) { mg in
                Circle().fill(Theme.muscleColor(mg)).frame(width: 8, height: 8)
            }
            Spacer(minLength: 0)
        }
    }

    /// PR 投稿（計測タイプ別トロフィー）。
    private var prBody: some View {
        HStack(spacing: metrics.spacing * 0.6) {
            ZStack {
                Circle().fill(Theme.celebration).frame(width: metrics.avatarSize * 1.25, height: metrics.avatarSize * 1.25)
                Image(systemName: entry.prKind?.symbol ?? "trophy.fill")
                    .font(metrics.exerciseName.bold())
                    .foregroundStyle(Theme.onLime)
            }
            VStack(alignment: .leading, spacing: 0) {
                // 「何の種目のベストか」を必ず出す（PostDetailView.prDetail と同じ並び）。
                if let name = entry.prExercise, !name.isEmpty {
                    Text(name).font(metrics.exerciseName.bold()).foregroundStyle(Theme.textPrimary)
                }
                if let kind = entry.prKind { OverlineLabel(text: kind.label) }
                if let v = entry.subtitle, !v.isEmpty {
                    Text(v).font(metrics.chipValue).foregroundStyle(Theme.lime)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// 描画スタイル。意匠は共通で、情報密度だけを切り替える。
enum PostCardStyle {
    /// アプリ内フィード・投稿プレビュー（写真中心・種目は 1 行要約）。
    case feed
    /// SNS へ出す画像（種目ごとに全セットを展開）。
    case share
}

/// スタイル別の寸法・書体。`.feed` は Dynamic Type に追従する意味付きフォント、
/// `.share` は ImageRenderer で決定的に焼くため基準幅に対する比率で決める。
struct PostCardMetrics {
    var authorName: Font
    var meta: Font
    var chipValue: Font
    var chipLabel: Font
    var caption: Font
    var exerciseName: Font
    var setText: Font
    var brand: Font
    var spacing: CGFloat
    var padding: CGFloat
    var photoHeight: CGFloat
    var avatarSize: CGFloat
    var cornerRadius: CGFloat

    static let feed = PostCardMetrics(
        authorName: .subheadline.bold(),
        meta: .caption2,
        chipValue: .subheadline.weight(.bold).monospacedDigit(),
        chipLabel: .system(size: 9, weight: .semibold),
        caption: .subheadline,
        exerciseName: .subheadline.weight(.semibold),
        setText: .caption.monospacedDigit(),
        brand: .caption2.bold(),
        spacing: Theme.Spacing.sm,
        padding: Theme.Spacing.md,
        photoHeight: 200,
        avatarSize: 32,
        cornerRadius: Theme.Radius.md
    )

    static func share(side: CGFloat) -> PostCardMetrics {
        PostCardMetrics(
            authorName: .system(size: side * 0.048, weight: .bold),
            meta: .system(size: side * 0.032, weight: .medium),
            chipValue: .system(size: side * 0.05, weight: .heavy, design: .rounded).monospacedDigit(),
            chipLabel: .system(size: side * 0.028, weight: .semibold),
            caption: .system(size: side * 0.04, weight: .medium),
            exerciseName: .system(size: side * 0.042, weight: .semibold),
            setText: .system(size: side * 0.034, weight: .medium).monospacedDigit(),
            brand: .system(size: side * 0.04, weight: .heavy, design: .rounded),
            spacing: side * 0.035,
            padding: side * 0.05,
            photoHeight: side * 0.62,
            avatarSize: side * 0.09,
            cornerRadius: side * 0.04
        )
    }
}
