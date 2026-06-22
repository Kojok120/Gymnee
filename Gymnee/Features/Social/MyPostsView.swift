import SwiftUI
import SwiftData

/// 自分の投稿一覧（§6.11）。チェックイン・ワークアウト・自己ベストを時系列で表示し、
/// スワイプで削除できる。削除はフィード表示の元データ（visit / workout / personal_record）を消す。
struct MyPostsView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalSyncEngine.self) private var sync
    @Query private var visits: [Visit]
    @Query private var prs: [PersonalRecord]
    @Query private var workouts: [Workout]
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.friends.rawValue

    init(userId: UUID) {
        self.userId = userId
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId }, sort: \Visit.visitedAt, order: .reverse)
        _prs = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId }, sort: \PersonalRecord.achievedAt, order: .reverse)
        _workouts = Query(filter: #Predicate<Workout> { $0.userId == userId }, sort: \Workout.date, order: .reverse)
    }

    private var entries: [FeedEntry] {
        FeedBuilder.build(
            visits: visits,
            personalRecords: prs,
            workouts: workouts,
            defaultVisibility: Visibility(rawValue: defaultVisibilityRaw) ?? .friends
        )
    }

    var body: some View {
        List {
            ForEach(entries) { entry in
                FeedCardView(entry: entry)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button("削除", role: .destructive) { delete(entry) }
                    }
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
                Button("閉じる") { dismiss() }
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
