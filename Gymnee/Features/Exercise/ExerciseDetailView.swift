import SwiftUI
import Charts

/// 種目詳細（§5 Exercise Detail）。推定1RM推移グラフ・PR・履歴。
struct ExerciseDetailView: View {
    let exercise: Exercise
    let userId: UUID

    /// 履歴の並び順（true=新しい順 / false=古い順）。
    @State private var historyNewestFirst = true

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let est1RM: Double
        let topWeight: Double
    }

    /// 1セッション分の履歴（日付＋その日の全セット）。
    private struct Session: Identifiable {
        let id: UUID
        let date: Date
        let sets: [ExerciseSet]
        let hasPR: Bool
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

            // 次回の目安（プログレッシブオーバーロード支援）。カードはミニマル原則で
            // 補助情報を載せないため、提案はこの詳細画面に置く。
            if let suggestion = nextSuggestion {
                Section {
                    ForEach(suggestion.rows, id: \.reps) { row in
                        HStack {
                            Text("\(row.reps)回").foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(SetFormatting.weightString(row.weight))kg")
                                .bold().monospacedDigit()
                        }
                    }
                } header: {
                    Text("次回の目安")
                } footer: {
                    Text("履歴ベストの推定1RM \(SetFormatting.weightString(suggestion.e1RM))kg からの逆算。各レップ数をこなせる理論上限なので、作業セットはこの少し下から。")
                }
            }

            Section("履歴") {
                Picker("並び順", selection: $historyNewestFirst) {
                    Text("新しい順").tag(true)
                    Text("古い順").tag(false)
                }
                .pickerStyle(.segmented)
                if sessions.isEmpty {
                    Text("記録なし").foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(session.date, format: .dateTime.year().month().day())
                                    .font(.subheadline.weight(.semibold))
                                if session.hasPR {
                                    Image(systemName: "trophy.fill").font(.caption).foregroundStyle(.yellow)
                                }
                                Spacer()
                            }
                            // その日に実施した全セット（重さ×回数／秒）を内訳表示。
                            Text(session.sets.map(\.detailText).joined(separator: "  "))
                                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 2)
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
                let valid = we.sets.filter { $0.weight > 0 && $0.reps > 0 }
                guard !valid.isEmpty else { return nil }
                let est = valid.map { OneRepMax.estimate(weight: $0.weight, reps: $0.reps) }.max() ?? 0
                let top = valid.map(\.weight).max() ?? 0
                return Point(date: date, est1RM: est, topWeight: top)
            }
            .sorted { $0.date < $1.date }
    }

    /// セッション別の履歴（新しい順）。各セッションの全セットを保持する。
    private var sessions: [Session] {
        exercise.workoutExercises
            .filter { $0.workout?.userId == userId && $0.workout?.completedAt != nil }
            .compactMap { we -> Session? in
                guard let date = we.workout?.date else { return nil }
                let valid = we.sets
                    .filter { $0.reps > 0 || ($0.durationSeconds ?? 0) > 0 }
                    .sorted { $0.setIndex < $1.setIndex }
                guard !valid.isEmpty else { return nil }
                return Session(id: we.id, date: date, sets: valid, hasPR: valid.contains { $0.isPR })
            }
            .sorted { historyNewestFirst ? $0.date > $1.date : $0.date < $1.date }
    }

    private var personalRecords: [PersonalRecord] {
        exercise.personalRecords.filter { $0.userId == userId }.sorted { $0.typeRaw < $1.typeRaw }
    }

    /// %1RM ベースのレップ別推奨重量（weight 種目で履歴があるときのみ）。
    /// 刻みは器具に合わせる（マシン/ケーブル=5kg、ケトルベル=4kg、他=2.5kg）。
    private var nextSuggestion: (e1RM: Double, rows: [(reps: Int, weight: Double)])? {
        guard exercise.measurementType == .weight else { return nil }
        let e1RM = WorkoutMetrics.bestE1RM(for: exercise, userId: userId, excludingWorkoutId: nil)
        guard e1RM > 0 else { return nil }
        let rows = StrengthSuggester.suggestions(e1RM: e1RM, increment: RecordSlots.weightStep(exercise))
            .filter { $0.weight > 0 }
        return rows.isEmpty ? nil : (e1RM, rows)
    }

    private func formatPR(_ pr: PersonalRecord) -> String {
        pr.type.formatted(pr.value)
    }
}
