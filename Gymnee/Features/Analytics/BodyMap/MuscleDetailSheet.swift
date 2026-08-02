import SwiftUI
import SwiftData

/// 人体図で部位をタップしたときの詳細。**その部位の種目とベスト（推定1RM 等）の一覧**を出す。
///
/// 以前は「部位内の全種目のトップセット重量」を 1 枚の折れ線に重ねていたが、
/// 見て終わりで次の行動につながらなかった。ここは一覧に徹し、種目をタップしたら
/// 既存の `ExerciseDetailView`（推定1RM 推移・自己ベスト・次回の目安・履歴）へ送る。
struct MuscleDetailSheet: View {
    let muscle: MuscleGroup
    let userId: UUID
    let status: MuscleFatigue.Status
    /// 今週この部位をどれだけやったか（人体図の塗りと同じ値）。
    let weekly: WeeklyMuscleLoad.Status

    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]

    init(muscle: MuscleGroup, userId: UUID, status: MuscleFatigue.Status, weekly: WeeklyMuscleLoad.Status) {
        self.muscle = muscle
        self.userId = userId
        self.status = status
        self.weekly = weekly
        let raw = muscle.rawValue
        _exercises = Query(filter: #Predicate<Exercise> { $0.muscleGroupRaw == raw }, sort: \Exercise.name)
    }

    /// 一覧 1 行分（種目 × ベスト × 最終実施日）。
    private struct Row: Identifiable {
        let id: UUID
        let exercise: Exercise
        /// ベストの種別（種目の計測タイプで変わる）。値が無ければ nil。
        let bestType: PRType?
        let bestValue: Double
        let lastPerformed: Date?
        let sessionCount: Int
    }

    /// この部位の種目のうち、**記録があるもの**だけを新しい順に並べる。
    /// 未記録の種目まで並べるとプリセットの山になって一覧が読めない。
    private var rows: [Row] {
        exercises.compactMap { ex -> Row? in
            let sessions = ex.workoutExercises.filter {
                $0.workout?.userId == userId && $0.workout?.completedAt != nil && !$0.sets.isEmpty
            }
            guard !sessions.isEmpty else { return nil }
            let last = sessions.compactMap { $0.workout?.completedAt }.max()
            let bests = WorkoutMetrics.bests(for: ex, userId: userId, excludingSetId: nil)
            let (type, value) = Self.headline(for: ex, bests: bests)
            return Row(id: ex.id, exercise: ex, bestType: type, bestValue: value,
                       lastPerformed: last, sessionCount: sessions.count)
        }
        .sorted { lhs, rhs in
            (lhs.lastPerformed ?? .distantPast) > (rhs.lastPerformed ?? .distantPast)
        }
    }

    /// 種目の計測タイプごとに「代表となるベスト」を選ぶ。
    /// ウェイトは推定1RM（重量↑もレップ↑も拾える）、自重は荷重モードで軸が変わる。
    private static func headline(for exercise: Exercise, bests: PRDetector.Bests) -> (PRType?, Double) {
        switch exercise.measurementType {
        case .weight:
            return bests.est1RM > 0 ? (.est1RM, bests.est1RM) : (nil, 0)
        case .bodyweight:
            switch exercise.loadMode {
            case .weighted:
                return bests.maxWeight > 0 ? (.maxWeight, bests.maxWeight) : (nil, 0)
            case .assisted:
                return bests.minAssist < .greatestFiniteMagnitude ? (.minAssist, bests.minAssist) : (nil, 0)
            case .none:
                return bests.maxReps > 0 ? (.maxReps, bests.maxReps) : (nil, 0)
            }
        case .time:
            return bests.maxDuration > 0 ? (.maxDuration, bests.maxDuration) : (nil, 0)
        case .cardio:
            return (nil, 0)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    weekCard
                    if rows.isEmpty {
                        EmptyStateView(systemImage: "dumbbell",
                                       title: "この部位の記録はまだありません",
                                       message: "ワークアウトを完了すると、種目ごとのベストと推移がここに並びます。")
                    } else {
                        exerciseList
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle(muscle.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } }
            }
        }
    }

    /// 今週の積み上げ（人体図の塗りと同じ意味）＋ 疲労の一言。
    private var weekCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("今週").font(.caption).foregroundStyle(Theme.textTertiary)
                Text("\(weekly.sets)")
                    .font(.numM).foregroundStyle(weekly.sets > 0 ? Theme.lime : Theme.textTertiary)
                Text("/ \(weekly.targetSets) セット").font(.caption).foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
                if let last = status.lastTrained {
                    Text("最終 \(last.formatted(.dateTime.month().day()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: weekly.progress)
                .tint(BodyMapView.loadColor(for: max(weekly.progress, 0.35)))
            HStack(spacing: 6) {
                Circle().fill(BodyMapView.fatigueColor(for: status.fatigue)).frame(width: 8, height: 8)
                Text(caption)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .gymneeCard()
    }

    private var caption: String {
        switch status.level {
        case .recovered:
            if weekly.isComplete { return "回復済み。今週の目安には届いています。" }
            return status.lastTrained == nil
                ? "まだこの部位の記録がありません。"
                : "回復済み。次に鍛える候補です。"
        case .recovering:
            return "回復中。軽めなら問題ありませんが、追い込むのは少し待つのが無難です。"
        case .fatigued:
            return "直近\(status.lastSetCount)セット。しっかり休ませたほうが伸びます。"
        }
    }

    /// 種目一覧。タップで種目詳細（推定1RM 推移・自己ベスト・履歴）へ。
    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "種目のベスト")
            ForEach(rows) { row in
                NavigationLink {
                    ExerciseDetailView(exercise: row.exercise, userId: userId)
                } label: {
                    exerciseRow(row)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func exerciseRow(_ row: Row) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.exercise.name)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle(row))
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                if let type = row.bestType {
                    Text(type.formatted(row.bestValue))
                        .font(.numS).foregroundStyle(Theme.textPrimary)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text(type.label).font(.caption2).foregroundStyle(Theme.textTertiary)
                } else {
                    Text("—").font(.numS).foregroundStyle(Theme.textTertiary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func subtitle(_ row: Row) -> String {
        let count = "\(row.sessionCount)回"
        guard let last = row.lastPerformed else { return count }
        return "\(count)・最終 \(last.formatted(.dateTime.month().day()))"
    }
}
