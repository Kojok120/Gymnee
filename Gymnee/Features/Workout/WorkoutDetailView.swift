import SwiftUI
import SwiftData

/// ワークアウト詳細（読み取り）。P2 でログ編集・前回値オートフィル・レストタイマーを実装する。
struct WorkoutDetailView: View {
    let workout: Workout

    @State private var showTimeEdit = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.date, format: .dateTime.year().month().day().weekday(.wide))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(headerStats).font(.caption).foregroundStyle(.secondary)
                }
                // 後追い記録で総合時間が実態と合わない場合の修正導線（完了済みのみ）。
                if workout.completedAt != nil {
                    Button { showTimeEdit = true } label: {
                        Label("時間を編集", systemImage: "clock")
                    }
                }
            }
            if let visit = workout.visit {
                Section("ジム活") {
                    Label(visit.gym?.name ?? "ジム", systemImage: "building.2.fill")
                }
            }
            ForEach(visibleExercises.sorted { $0.orderIndex < $1.orderIndex }) { we in
                Section(we.exercise?.name ?? "種目") {
                    ForEach(we.sets.sorted { $0.setIndex < $1.setIndex }) { set in
                        HStack {
                            Text("セット\(set.setIndex + 1)").foregroundStyle(.secondary)
                            Spacer()
                            Text(set.detailText).monospacedDigit()
                            if set.isPR {
                                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTimeEdit) {
            WorkoutTimeEditSheet(workout: workout)
        }
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

    private var totalSets: Int {
        workout.exercises.reduce(0) { $0 + $1.sets.count }
    }

    private var totalVolume: Int {
        let v = workout.exercises.flatMap(\.sets).reduce(0.0) { $0 + $1.volume }
        return v.isFinite ? Int(v) : 0   // 非有限混入時も Int(∞) でトラップしない
    }

    /// 表示する種目（セットのある種目のみ。ヘッダ集計と本文セクションで基準を揃える）。
    private var visibleExercises: [WorkoutExercise] {
        workout.exercises.filter { !$0.sets.isEmpty }
    }

    /// ヘッダの集計行（種目数・セット数・総容量・所要時間）。
    private var headerStats: String {
        var parts = ["\(visibleExercises.count)種目", "\(totalSets)セット", "総容量 \(totalVolume)kg"]
        if let mins = WorkoutDuration.minutes(
            date: workout.date, completedAt: workout.completedAt, durationSeconds: workout.durationSeconds
        ) {
            parts.append("\(mins)分")
        }
        return parts.joined(separator: "・")
    }
}
