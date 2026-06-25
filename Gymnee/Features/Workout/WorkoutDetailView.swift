import SwiftUI
import SwiftData

/// ワークアウト詳細（読み取り）。P2 でログ編集・前回値オートフィル・レストタイマーを実装する。
struct WorkoutDetailView: View {
    let workout: Workout

    var body: some View {
        List {
            if let visit = workout.visit {
                Section("来店") {
                    Label(visit.gym?.name ?? "ジム", systemImage: "building.2.fill")
                }
            }
            ForEach(workout.exercises.sorted { $0.orderIndex < $1.orderIndex }) { we in
                Section(we.exercise?.name ?? "種目") {
                    if we.sets.isEmpty {
                        Text("セットなし").foregroundStyle(.secondary)
                    } else {
                        ForEach(we.sets.sorted { $0.setIndex < $1.setIndex }) { set in
                            HStack {
                                Text("セット\(set.setIndex + 1)").foregroundStyle(.secondary)
                                Spacer()
                                Text("\(set.weight, format: .number)kg × \(set.reps)")
                                if set.isPR {
                                    Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // 編集はロガー画面を再利用（セット・種目の追加/修正、完了の付け直しが可能）。
                NavigationLink {
                    RecordContent(userId: workout.userId, resuming: workout)
                } label: {
                    Text("編集")
                }
            }
        }
    }
}
