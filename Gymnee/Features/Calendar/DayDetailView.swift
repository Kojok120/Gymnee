import SwiftUI
import SwiftData

/// 日別詳細（§5 Day Detail）。その日の来店・写真・ワークアウト一覧。
struct DayDetailView: View {
    let userId: UUID
    let date: Date
    /// ワークアウト編集を開く。pushed view 上では navigationDestination が無効(iOS26.5)なため、
    /// ロガーへの遷移はルート(CalendarHomeContent)側に委ねる。
    var onEditWorkout: (Workout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Query private var visits: [Visit]
    @Query private var workouts: [Workout]

    private let calendar = Calendar.current

    init(userId: UUID, date: Date, onEditWorkout: @escaping (Workout) -> Void = { _ in }) {
        self.userId = userId
        self.date = date
        self.onEditWorkout = onEditWorkout
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _visits = Query(
            filter: #Predicate<Visit> { $0.userId == userId && $0.visitedAt >= start && $0.visitedAt < end },
            sort: \Visit.visitedAt, order: .reverse
        )
        _workouts = Query(
            filter: #Predicate<Workout> { $0.userId == userId && $0.date >= start && $0.date < end },
            sort: \Workout.date, order: .reverse
        )
    }

    var body: some View {
        List {
            Section("来店") {
                if visits.isEmpty {
                    Text("来店記録なし").foregroundStyle(.secondary)
                } else {
                    ForEach(visits) { visit in
                        VisitRow(visit: visit)
                            .swipeActions {
                                Button("削除", role: .destructive) { delete(visit) }
                            }
                    }
                }
            }

            Section("ワークアウト") {
                if workouts.isEmpty {
                    Text("ワークアウト記録なし").foregroundStyle(.secondary)
                } else {
                    ForEach(workouts) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            WorkoutRow(workout: workout)
                        }
                    }
                }
                Button { addWorkout() } label: {
                    Label("この日にワークアウトを追加", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// その日（過去でも未来でも）にワークアウトを新規作成してロガーを開く。記録の後追い入力・先取り計画に。
    private func addWorkout() {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let workout = Workout(userId: userId, date: noon, name: "ワークアウト")
        context.insert(workout)
        try? context.save()
        onEditWorkout(workout)
    }

    private var titleText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E)"
        return f.string(from: date)
    }

    private func delete(_ visit: Visit) {
        let visitId = visit.id
        PhotoStore.delete(visit.localPhotoFilename)
        context.delete(visit)
        try? context.save()
        sync.enqueue(PendingChange(entity: "visits", recordId: visitId, operation: .delete, updatedAt: .now))
    }
}
