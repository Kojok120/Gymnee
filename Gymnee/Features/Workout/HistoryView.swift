import SwiftUI
import SwiftData

/// 記録一覧（トレーニング履歴）。上部セグメントで「日付ごと / 種目ごと」を切替える。
/// 分析タブ先頭・記録タブの開始ゲートの2箇所から push される前提のため、
/// 自前の `NavigationStack` は持たない（ホスト側スタックに乗る）。
struct HistoryView: View {
    let userId: UUID

    enum Axis: String, CaseIterable, Identifiable {
        case date, exercise
        var id: String { rawValue }
        var label: String { self == .date ? "日付ごと" : "種目ごと" }
    }

    @State private var axis: Axis = .date

    var body: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $axis) {
                ForEach(Axis.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(Theme.Spacing.md)

            switch axis {
            case .date: DateHistoryList(userId: userId)
            case .exercise: ExerciseHistoryList(userId: userId)
            }
        }
        .background(Theme.bg0)
        .navigationTitle("記録一覧")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 日付ごと

/// 全期間の完了ワークアウトを日付降順で取得し、月ごとにセクション分けして並べる。
private struct DateHistoryList: View {
    let userId: UUID
    @Query private var workouts: [Workout]
    /// 進行中の下書き（未完了・予定でない）。中身のあるものだけ「下書き」として一覧先頭に出す。
    @Query private var draftWorkouts: [Workout]

    private let calendar = Calendar.current

    init(userId: UUID) {
        self.userId = userId
        // 完了済みのみ。全期間（DEV のため件数上限なし）。
        _workouts = Query(
            filter: #Predicate<Workout> { $0.userId == userId && $0.completedAt != nil },
            sort: \Workout.date, order: .reverse
        )
        _draftWorkouts = Query(
            filter: #Predicate<Workout> { $0.userId == userId && $0.completedAt == nil && $0.isPlanned == false },
            sort: \Workout.date, order: .reverse
        )
    }

    /// セット or メモのある下書きだけ（空の中断は出さない）。
    private var drafts: [Workout] {
        draftWorkouts.filter { $0.exercises.contains { !$0.sets.isEmpty } || !($0.note ?? "").isEmpty }
    }

    var body: some View {
        if workouts.isEmpty && drafts.isEmpty {
            EmptyStateView(
                systemImage: "calendar",
                title: "記録がありません",
                message: "ワークアウトを完了すると、ここに履歴が並びます。"
            )
        } else {
            List {
                if !drafts.isEmpty {
                    Section("下書き（途中の記録）") {
                        ForEach(drafts) { draft in draftRow(draft) }
                    }
                }
                ForEach(grouped, id: \.month) { group in
                    Section(monthLabel(group.month)) {
                        ForEach(group.items) { workout in
                            NavigationLink {
                                WorkoutDetailView(workout: workout)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(workout.date, format: .dateTime.month().day().weekday(.abbreviated))
                                        .font(.caption).foregroundStyle(.secondary)
                                    WorkoutRow(workout: workout)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// 下書き行。タップで「途中の記録」と同じ再開導線（記録タブで当該ワークアウトを開く）。
    private func draftRow(_ draft: Workout) -> some View {
        Button {
            NotificationCenter.default.post(name: .gymneeStartWorkout, object: nil,
                                            userInfo: ["workoutId": draft.id.uuidString])
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(draft.date, format: .dateTime.month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                    Text("下書き")
                        .font(.caption2.bold()).foregroundStyle(Theme.onLime)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.limeFill, in: Capsule())
                    Spacer()
                    Image(systemName: "arrow.uturn.backward.circle").font(.caption).foregroundStyle(Theme.lime)
                }
                Text(DraftSummary.text(for: draft))
                    .font(.subheadline).foregroundStyle(Theme.textPrimary).lineLimit(2)
            }
        }
    }

    private func monthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.year().month())
    }

    /// 取得済み（日付降順）を月ごとにまとめる。順序は降順を維持。
    private var grouped: [(month: Date, items: [Workout])] {
        var order: [Date] = []
        var map: [Date: [Workout]] = [:]
        for w in workouts {
            let m = monthStart(w.date)
            if map[m] == nil { order.append(m) }
            map[m, default: []].append(w)
        }
        return order.map { ($0, map[$0] ?? []) }
    }
}

// MARK: - 種目ごと

/// 履歴のある種目（当該ユーザーの完了ワークアウトのセットを1つ以上持つ）だけを部位別に並べる。
private struct ExerciseHistoryList: View {
    let userId: UUID
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    /// 履歴のある種目（検索フィルタ前）。重い関連走査なので検索ごとには作り直さずキャッシュする。
    @State private var baseExercises: [Exercise] = []

    var body: some View {
        Group {
            if baseExercises.isEmpty {
                EmptyStateView(
                    systemImage: "dumbbell",
                    title: "種目の記録がありません",
                    message: "ワークアウトを完了すると、種目ごとの履歴が見られます。"
                )
            } else {
                List {
                    if grouped.isEmpty {
                        Text("該当する種目がありません").foregroundStyle(.secondary)
                    } else {
                        ForEach(grouped, id: \.muscle) { group in
                            Section(group.muscle.label) {
                                ForEach(group.items) { exercise in
                                    NavigationLink {
                                        ExerciseDetailView(exercise: exercise, userId: userId)
                                    } label: {
                                        HStack {
                                            Text(exercise.name)
                                            Spacer()
                                            Text(exercise.equipment.label)
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .searchable(text: $search, prompt: "種目を検索")
            }
        }
        // 種目数が変わった時だけ再集計（検索1文字ごとの全関連走査を避ける）。
        .task(id: exercises.count) { rebuildBase() }
    }

    /// 履歴のある種目を集計して `baseExercises` に保持する。空状態判定とグルーピングの土台。
    private func rebuildBase() {
        baseExercises = exercises.filter { ex in
            ex.workoutExercises.contains { we in
                we.workout?.userId == userId && we.workout?.completedAt != nil && !we.sets.isEmpty
            }
        }
    }

    /// 検索フィルタ適用後、部位別にグルーピング（部位ラベル昇順・種目名昇順）。
    private var grouped: [(muscle: MuscleGroup, items: [Exercise])] {
        let filtered = search.isEmpty
            ? baseExercises
            : baseExercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
        let byMuscle = Dictionary(grouping: filtered, by: { $0.muscleGroup })
        return byMuscle.keys
            .sorted { $0.label < $1.label }
            .map { ($0, (byMuscle[$0] ?? []).sorted { $0.name < $1.name }) }
    }
}
