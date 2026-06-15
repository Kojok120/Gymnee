import SwiftUI
import SwiftData

/// 日別詳細（§5 Day Detail）。その日の来店・写真・ワークアウト一覧。
struct DayDetailView: View {
    let userId: UUID
    let date: Date

    @Environment(\.modelContext) private var context
    @Query private var visits: [Visit]
    @Query private var workouts: [Workout]

    private let calendar = Calendar.current

    init(userId: UUID, date: Date) {
        self.userId = userId
        self.date = date
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
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var titleText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E)"
        return f.string(from: date)
    }

    private func delete(_ visit: Visit) {
        PhotoStore.delete(visit.localPhotoFilename)
        context.delete(visit)
        try? context.save()
    }
}
