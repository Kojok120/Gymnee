import SwiftUI
import Charts

/// 種目詳細（§5 Exercise Detail）。推定1RM推移グラフ・PR・履歴。
struct ExerciseDetailView: View {
    let exercise: Exercise
    let userId: UUID

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let est1RM: Double
        let topWeight: Double
    }

    var body: some View {
        List {
            Section("推定1RM 推移") {
                if points.count >= 2 {
                    chart.frame(height: 200)
                } else {
                    Text("データが増えると推移グラフが表示されます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("自己ベスト") {
                if personalRecords.isEmpty {
                    Text("まだ記録がありません。").foregroundStyle(.secondary)
                } else {
                    ForEach(personalRecords) { pr in
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                            Text(pr.type.label)
                            Spacer()
                            Text(formatPR(pr))
                                .bold()
                        }
                    }
                }
            }

            Section("履歴") {
                if history.isEmpty {
                    Text("記録なし").foregroundStyle(.secondary)
                } else {
                    ForEach(history) { point in
                        HStack {
                            Text(point.date, format: .dateTime.year().month().day())
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "推定1RM %.1fkg", point.est1RM))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chart: some View {
        Chart(points) { p in
            LineMark(x: .value("日付", p.date), y: .value("推定1RM", p.est1RM))
                .foregroundStyle(Theme.energy)
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("日付", p.date), y: .value("推定1RM", p.est1RM))
                .foregroundStyle(Theme.energy)
        }
        .chartYAxisLabel("kg")
    }

    private var points: [Point] {
        exercise.workoutExercises
            .filter { $0.workout?.userId == userId }
            .compactMap { we -> Point? in
                guard let date = we.workout?.date else { return nil }
                let valid = we.sets.filter { $0.type != .warmup && $0.weight > 0 && $0.reps > 0 }
                guard !valid.isEmpty else { return nil }
                let est = valid.map { OneRepMax.estimate(weight: $0.weight, reps: $0.reps) }.max() ?? 0
                let top = valid.map(\.weight).max() ?? 0
                return Point(date: date, est1RM: est, topWeight: top)
            }
            .sorted { $0.date < $1.date }
    }

    private var history: [Point] { points.reversed() }

    private var personalRecords: [PersonalRecord] {
        exercise.personalRecords.filter { $0.userId == userId }.sorted { $0.typeRaw < $1.typeRaw }
    }

    private func formatPR(_ pr: PersonalRecord) -> String {
        switch pr.type {
        case .maxWeight: return String(format: "%.1f kg", pr.value)
        case .maxReps: return "\(Int(pr.value)) reps"
        case .est1RM: return String(format: "%.1f kg", pr.value)
        case .maxVolume: return String(format: "%.0f kg", pr.value)
        }
    }
}
