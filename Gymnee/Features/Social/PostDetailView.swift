import SwiftUI
import SwiftData

/// 投稿（feed_item）の詳細画面（Twitter 風）。フィード／自分の投稿のカードをタップして開く。
/// 全投稿種別（ワークアウト／PR／来店）・自分/他人の投稿の双方で同じ詳細を開ける（`FeedEntry` だけで完結）。
/// 構成: ①種別ごとのリッチ詳細 → ②リアクションした人 → ③コメント一覧＋入力。
/// 自分の投稿はローカル実体（Workout/PR/Visit）から深い詳細を描き、他人の投稿は feed_item の範囲で描く。
struct PostDetailView: View {
    let entry: FeedEntry
    let currentUserId: UUID
    var currentUserName: String?
    var onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync

    @Query private var reactions: [PostReaction]
    @Query private var comments: [Comment]
    @Query private var blocks: [Block]
    @Query private var profiles: [Profile]
    // 自分の投稿のときだけ実体が引ける（他人の投稿はローカルに無い＝nil）。
    @Query private var ownWorkouts: [Workout]
    @Query private var ownVisits: [Visit]
    @Query private var ownPRs: [PersonalRecord]

    @State private var draft = ""
    /// 編集中の自分のコメント（非nilならコンポーザーは編集モード）。
    @State private var editingComment: Comment?
    @State private var reportTarget: CommentReportTarget?
    @State private var editVisit: Visit?
    @FocusState private var composerFocused: Bool

    init(entry: FeedEntry, currentUserId: UUID, currentUserName: String? = nil, onClose: @escaping () -> Void) {
        self.entry = entry
        self.currentUserId = currentUserId
        self.currentUserName = currentUserName
        self.onClose = onClose
        let id = entry.id
        _reactions = Query(filter: #Predicate<PostReaction> { $0.feedItemId == id }, sort: \PostReaction.createdAt, order: .reverse)
        _comments = Query(filter: #Predicate<Comment> { $0.feedItemId == id }, sort: \Comment.createdAt, order: .forward)
        _blocks = Query(filter: #Predicate<Block> { $0.blockerId == currentUserId })
        _ownWorkouts = Query(filter: #Predicate<Workout> { $0.id == id })
        _ownVisits = Query(filter: #Predicate<Visit> { $0.id == id })
        _ownPRs = Query(filter: #Predicate<PersonalRecord> { $0.id == id })
    }

    private var blockedIds: Set<UUID> { Set(blocks.map(\.blockedId)) }
    private var visibleComments: [Comment] { comments.filter { !blockedIds.contains($0.userId) } }
    private var visibleReactions: [PostReaction] { reactions.filter { !blockedIds.contains($0.userId) } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        authorCard
                        detailExtras
                        reactionsSection
                        Divider().overlay(Theme.bg3)
                        commentsSection
                    }
                    .padding(Theme.Spacing.md)
                }
                composer
            }
            .background(Theme.bg0)
            .navigationTitle("投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { onClose() } }
            }
            .navigationDestination(for: UserRef.self) { ref in
                UserProfileView(targetUserId: ref.id, currentUserId: currentUserId, fallbackName: ref.name)
            }
            .sheet(item: $reportTarget) { t in
                ReportSheet(reporterId: currentUserId, reportedUserId: t.userId,
                            reportedDisplayName: t.name, contextType: "comment", contextId: t.id)
            }
            .sheet(item: $editVisit) { visit in
                CheckInEditView(visit: visit, visibilityStore: PostVisibilityStore())
            }
            .task(id: reactions.count + comments.count) { await ensureProfiles() }
        }
    }

    // MARK: - 投稿カード（他人の投稿は著者タップでプロフィールへ）

    /// 著者表示名（空文字も「ユーザー」に正規化。commentName(_:) と同方針）。
    private var authorDisplayName: String {
        if let n = entry.authorName, !n.isEmpty { return n }
        return "ユーザー"
    }

    @ViewBuilder private var authorCard: some View {
        if let authorId = entry.authorId, authorId != currentUserId {
            NavigationLink(value: UserRef(id: authorId, name: authorDisplayName)) {
                FeedCardView(entry: entry)
            }
            .buttonStyle(.plain)
        } else {
            FeedCardView(entry: entry)
        }
    }

    // MARK: - ①種別ごとのリッチ詳細

    @ViewBuilder private var detailExtras: some View {
        switch entry.kind {
        case .workout:
            if let w = ownWorkouts.first { workoutDetail(w) }                       // 自分: ローカル実体（編集導線つき）
            else if let lines = entry.workoutLines, !lines.isEmpty { othersWorkoutMenu(lines) }  // 他人: feed の内訳
        case .pr:
            prDetail
        case .visit:
            if let v = ownVisits.first { visitDetail(v) }                           // 他人の写真はカード（FeedCardView）に表示
        }
    }

    /// ワークアウト: 種目ごとのセット内訳 ＋ 編集できる詳細への導線（自分の投稿）。
    private func workoutDetail(_ w: Workout) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("メニュー", systemImage: "list.bullet")
            // セット0件の種目は表示しない（記録ミスで残った空種目を投稿に出さない）。
            ForEach(w.exercises.filter { !$0.sets.isEmpty }.sorted { $0.orderIndex < $1.orderIndex }) { we in
                VStack(alignment: .leading, spacing: 4) {
                    Text(we.exercise?.name ?? "種目")
                        .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                    ForEach(we.sets.sorted { $0.setIndex < $1.setIndex }) { set in
                        HStack {
                            Text("セット\(set.setIndex + 1)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(set.detailText).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textPrimary)
                            if set.isPR { Image(systemName: "trophy.fill").font(.caption).foregroundStyle(.yellow) }
                        }
                    }
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
            NavigationLink {
                WorkoutDetailView(workout: w)
            } label: {
                Label("トレーニングの詳細・編集", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.lime)
            }
            .padding(.top, 2)
        }
    }

    /// 他人のワークアウト: feed の statsJSON に載った種目別セット内訳を、自分の投稿と同じ体裁で描く（編集導線なし）。
    private func othersWorkoutMenu(_ lines: [FeedItemStats.ExerciseLine]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("メニュー", systemImage: "list.bullet")
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.name).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                    ForEach(Array(line.sets.enumerated()), id: \.offset) { i, set in
                        HStack {
                            Text("セット\(i + 1)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(set.text).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textPrimary)
                            if set.isPR { Image(systemName: "trophy.fill").font(.caption).foregroundStyle(.yellow) }
                        }
                    }
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
        }
    }

    /// PR: 計測タイプ別トロフィー・種目名・記録値・達成日（自分/他人とも feed の範囲で描ける）。
    @ViewBuilder private var prDetail: some View {
        let pr = ownPRs.first
        let kind = pr?.type ?? entry.prKind ?? .maxWeight
        let valueText = pr.map { $0.type.formatted($0.value) } ?? (entry.subtitle ?? "")
        let exName = pr?.exercise?.name
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("自己ベスト", systemImage: "trophy.fill")
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle().fill(Theme.celebration).frame(width: 52, height: 52)
                    Image(systemName: kind.symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.onLime)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let exName, !exName.isEmpty {
                        Text(exName).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                    }
                    OverlineLabel(text: kind.label)
                    Text(valueText).font(.numS).foregroundStyle(Theme.lime)
                }
                Spacer(minLength: 0)
            }
            Label(entry.date.formatted(.dateTime.year().month().day()), systemImage: "calendar")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    /// 来店: ジム・日時・合トレ相手・メモ ＋ 編集導線（自分の投稿）。
    private func visitDetail(_ v: Visit) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("来店", systemImage: "building.2.fill")
            Label(v.gym?.name ?? "ジム", systemImage: "building.2.fill")
                .font(.subheadline).foregroundStyle(Theme.textPrimary)
            Label(v.visitedAt.formatted(.dateTime.year().month().day().hour().minute()), systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
            if !v.partners.isEmpty {
                Label(v.partners.compactMap { $0.partnerDisplayName }.joined(separator: "・"), systemImage: "person.2.fill")
                    .font(.caption).foregroundStyle(Theme.energy)
            }
            if let note = v.note, !note.isEmpty {
                Text(note).font(.subheadline).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { editVisit = v } label: {
                Label("来店を編集", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.lime)
            }
            .padding(.top, 2)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    // MARK: - ②リアクションした人

    @ViewBuilder private var reactionsSection: some View {
        if visibleReactions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("リアクション", systemImage: "heart")
                Text("まだリアクションはありません。").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeader("リアクション \(visibleReactions.count)", systemImage: "heart.fill")
                ForEach(visibleReactions) { r in
                    reactorRow(r)
                }
            }
        }
    }

    @ViewBuilder private func reactorRow(_ r: PostReaction) -> some View {
        let isMe = r.userId == currentUserId
        let label = HStack(spacing: 10) {
            AvatarView(urlString: avatarURL(r.userId), size: 32)
            Text(isMe ? "あなた" : name(r.userId))
                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            Text(ReactionKind(rawValue: r.kindRaw)?.emoji ?? "❤️").font(.subheadline)
        }
        if isMe {
            label
        } else {
            NavigationLink(value: UserRef(id: r.userId, name: name(r.userId))) { label }
                .buttonStyle(.plain)
        }
    }

    // MARK: - ③コメント

    @ViewBuilder private var commentsSection: some View {
        sectionHeader(visibleComments.isEmpty ? "コメント" : "コメント \(visibleComments.count)", systemImage: "bubble.left.and.bubble.right.fill")
        if visibleComments.isEmpty {
            Text("最初のコメントを送りましょう。").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(visibleComments) { c in commentRow(c) }
        }
    }

    @ViewBuilder
    private func commentRow(_ c: Comment) -> some View {
        let body = HStack(alignment: .top, spacing: 10) {
            AvatarView(urlString: avatarURL(c.userId), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(commentName(c)).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                    Text(c.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(c.text).font(.subheadline).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        // 他人のコメントはタップで投稿者プロフィール（フレンド詳細）へ。自分のコメントは遷移なし。
        Group {
            if c.userId != currentUserId {
                NavigationLink(value: UserRef(id: c.userId, name: commentName(c))) { body }
                    .buttonStyle(.plain)
            } else {
                body
            }
        }
        .contextMenu {
            if c.userId == currentUserId {
                Button("編集", systemImage: "pencil") { startEdit(c) }
                Button("削除", systemImage: "trash", role: .destructive) { deleteComment(c) }
            } else {
                Button("通報", systemImage: "flag") {
                    reportTarget = CommentReportTarget(id: c.id, userId: c.userId, name: commentName(c))
                }
                Button("ブロック", systemImage: "hand.raised", role: .destructive) {
                    Moderation.block(blockerId: currentUserId, blockedId: c.userId, displayName: commentName(c), context: context, sync: sync)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if editingComment != nil {
                HStack(spacing: 6) {
                    Image(systemName: "pencil").font(.caption2)
                    Text("コメントを編集中").font(.caption2)
                    Spacer(minLength: 0)
                    Button("キャンセル") { cancelEdit() }.font(.caption2)
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.xs)
            }
            HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                TextField(editingComment == nil ? "コメントを追加…" : "コメントを編集…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.vertical, 8).padding(.horizontal, Theme.Spacing.md)
                    .background(Theme.bg2, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                Button { submit() } label: {
                    Image(systemName: editingComment == nil ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? Theme.lime : Theme.textTertiary)
                }
                .disabled(!canSend)
                .sensoryFeedback(.success, trigger: visibleComments.count)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.bg1)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.bold)).foregroundStyle(Theme.textSecondary)
    }

    private func name(_ id: UUID) -> String {
        if let n = profiles.first(where: { $0.id == id })?.displayName, !n.isEmpty { return n }
        return "ユーザー"
    }
    private func commentName(_ c: Comment) -> String {
        if let n = profiles.first(where: { $0.id == c.userId })?.displayName, !n.isEmpty { return n }
        if let n = c.authorDisplayName, !n.isEmpty { return n }
        return "ユーザー"
    }
    private func avatarURL(_ id: UUID) -> String? { profiles.first(where: { $0.id == id })?.avatarURL }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { (1...500).contains(trimmedDraft.count) }

    /// 反応者・コメント者のプロフィール（名前/アバター）が未取得なら取りに行く。
    private func ensureProfiles() async {
        var ids = Set(reactions.map(\.userId))
        ids.formUnion(comments.map(\.userId))
        ids.subtract(profiles.map(\.id))
        ids.remove(currentUserId)
        if !ids.isEmpty { await sync.ensureProfiles(ids: ids) }
    }

    /// 送信ボタン：編集モードなら更新、通常なら新規投稿。
    private func submit() {
        if editingComment != nil { saveEdit() } else { send() }
    }

    private func send() {
        let t = trimmedDraft
        guard (1...500).contains(t.count) else { return }
        let c = Comment(feedItemId: entry.id, userId: currentUserId, authorDisplayName: currentUserName, text: t)
        context.insert(c)
        try? context.save()
        sync.enqueue(PendingChange(entity: "comments", recordId: c.id, operation: .upsert, updatedAt: c.updatedAt))
        draft = ""
        composerFocused = false
        Task { await sync.syncNow() }
    }

    /// 自分のコメントを編集開始（コンポーザーを編集モードに）。
    private func startEdit(_ c: Comment) {
        editingComment = c
        draft = c.text
        composerFocused = true
    }

    /// 編集内容を保存（本人のみ・RLS comments_modify_own）。updated_at 更新で LWW 反映。
    private func saveEdit() {
        guard let c = editingComment else { return }
        let t = trimmedDraft
        guard (1...500).contains(t.count) else { return }
        c.text = t
        c.updatedAt = .now
        c.isDirty = true
        try? context.save()
        sync.enqueue(PendingChange(entity: "comments", recordId: c.id, operation: .upsert, updatedAt: c.updatedAt))
        cancelEdit()
        Task { await sync.syncNow() }
    }

    private func cancelEdit() {
        editingComment = nil
        draft = ""
        composerFocused = false
    }

    private func deleteComment(_ c: Comment) {
        let id = c.id
        context.delete(c)
        try? context.save()
        sync.enqueue(PendingChange(entity: "comments", recordId: id, operation: .delete, updatedAt: .now))
    }
}

/// コメント通報シート提示用ターゲット（`sheet(item:)` 用）。
struct CommentReportTarget: Identifiable {
    let id: UUID      // commentId（reports.context_id）
    let userId: UUID  // reportedUserId
    let name: String
}
