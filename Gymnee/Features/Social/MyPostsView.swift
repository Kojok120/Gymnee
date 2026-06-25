import SwiftUI
import SwiftData

/// 自分の投稿一覧（§6.11）。チェックイン・ワークアウト・自己ベストを時系列で表示し、
/// スワイプで削除できる。削除はフィード表示の元データ（visit / workout / personal_record）を消す。
struct MyPostsView: View {
    let userId: UUID
    /// シートを閉じる。NavigationStack 内の \.dismiss はシートを閉じないため明示的に渡す。
    var onClose: () -> Void
    let visibilityStore: PostVisibilityStore

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Query private var visits: [Visit]
    @Query private var prs: [PersonalRecord]
    @Query private var workouts: [Workout]
    @Query private var allReactions: [PostReaction]
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.friends.rawValue
    @State private var editVisit: Visit?

    init(userId: UUID, visibilityStore: PostVisibilityStore, onClose: @escaping () -> Void) {
        self.userId = userId
        self.visibilityStore = visibilityStore
        self.onClose = onClose
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId }, sort: \Visit.visitedAt, order: .reverse)
        _prs = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId }, sort: \PersonalRecord.achievedAt, order: .reverse)
        _workouts = Query(filter: #Predicate<Workout> { $0.userId == userId }, sort: \Workout.date, order: .reverse)
    }

    private var defaultVisibility: Visibility { Visibility(rawValue: defaultVisibilityRaw) ?? .public }

    private var entries: [FeedEntry] {
        FeedBuilder.build(
            visits: visits,
            personalRecords: prs,
            workouts: workouts,
            defaultVisibility: defaultVisibility,
            visibilityStore: visibilityStore
        )
    }

    var body: some View {
        // 毎描画の O(N^2) first(where:) を避けるため id 索引と reaction を一度だけ構築。
        let reactionsByItem = Dictionary(grouping: allReactions, by: \.feedItemId)
        let workoutsById = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let visitsById = Dictionary(visits.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return List {
            ForEach(entries) { entry in
                row(entry, reactions: reactionsByItem[entry.id] ?? [], workout: workoutsById[entry.id], visit: visitsById[entry.id])
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button("削除", role: .destructive) { delete(entry) }
                    }
                    .contextMenu { postMenu(entry) }
            }
        }
        .listStyle(.plain)
        .background(Theme.groupedBackground)
        .overlay {
            if entries.isEmpty {
                EmptyStateView(systemImage: "square.stack.3d.up", title: "投稿がありません", message: "チェックイン・ワークアウト・自己ベストがここに並びます。")
            }
        }
        .navigationTitle("自分の投稿")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("閉じる") { onClose() }
            }
        }
        .sheet(item: $editVisit) { visit in
            CheckInEditView(visit: visit, visibilityStore: visibilityStore)
        }
    }

    /// カード（タップで開く）＋いいね/応援バー。
    private func row(_ entry: FeedEntry, reactions: [PostReaction], workout: Workout?, visit: Visit?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            card(entry, workout: workout, visit: visit)
            ReactionBar(feedItemId: entry.id, userId: userId, reactions: reactions)
        }
    }

    /// タップで開く（ワークアウト＝詳細、チェックイン＝編集）。仕様を統一。
    @ViewBuilder
    private func card(_ entry: FeedEntry, workout: Workout?, visit: Visit?) -> some View {
        if entry.kind == .workout, let workout {
            NavigationLink {
                WorkoutDetailView(workout: workout)
            } label: {
                FeedCardView(entry: entry)
            }
            .buttonStyle(.plain)
        } else if entry.kind == .visit, let visit {
            Button { editVisit = visit } label: { FeedCardView(entry: entry) }
                .buttonStyle(.plain)
        } else {
            FeedCardView(entry: entry)
        }
    }

    /// 投稿の長押しメニュー：公開範囲の変更（編集はカードのタップで開く）。
    @ViewBuilder
    private func postMenu(_ entry: FeedEntry) -> some View {
        Menu("公開範囲") {
            ForEach(Visibility.allCases, id: \.self) { v in
                Button { visibilityStore.set(v, for: entry.id) } label: {
                    Label(v.label, systemImage: (visibilityStore.visibility(for: entry.id) ?? defaultVisibility) == v ? "checkmark" : "")
                }
            }
        }
    }

    private func delete(_ entry: FeedEntry) {
        switch entry.kind {
        case .visit:
            guard let v = visits.first(where: { $0.id == entry.id }) else { return }
            PhotoStore.delete(v.localPhotoFilename)
            context.delete(v)
            try? context.save()
            sync.enqueue(PendingChange(entity: "visits", recordId: entry.id, operation: .delete, updatedAt: .now))
        case .pr:
            guard let pr = prs.first(where: { $0.id == entry.id }) else { return }
            context.delete(pr)
            try? context.save()
            sync.enqueue(PendingChange(entity: "personal_records", recordId: entry.id, operation: .delete, updatedAt: .now))
        case .workout:
            guard let w = workouts.first(where: { $0.id == entry.id }) else { return }
            context.delete(w)
            try? context.save()
            sync.enqueue(PendingChange(entity: "workouts", recordId: entry.id, operation: .delete, updatedAt: .now))
        }
    }
}
