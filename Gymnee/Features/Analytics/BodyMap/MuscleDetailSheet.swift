import SwiftUI
import SwiftData
import Charts

/// 人体図で部位をタップしたときの詳細。**その部位の種目ごとの重量推移**を重ねて見せる。
///
/// 軸は推定1RM ではなく「そのセッションのトップセット重量」。
/// 実際に挙げた数字がそのまま並ぶ方が、伸びているかを直感的に判断できるため
/// （推定1RM は式依存で、レップ数が変わると跳ねて見える）。
struct MuscleDetailSheet: View {
    let muscle: MuscleGroup
    let userId: UUID
    let status: MuscleFatigue.Status

    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]

    init(muscle: MuscleGroup, userId: UUID, status: MuscleFatigue.Status) {
        self.muscle = muscle
        self.userId = userId
        self.status = status
        let raw = muscle.rawValue
        _exercises = Query(filter: #Predicate<Exercise> { $0.muscleGroupRaw == raw }, sort: \Exercise.name)
    }

    /// 折れ線 1 点（種目 × 日付 × トップ重量）。
    private struct Point: Identifiable {
        let id = UUID()
        let exercise: String
        let date: Date
        let topWeight: Double
    }

    /// 直近 6 ヶ月・この部位の全種目のトップセット。
    private var points: [Point] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .distantPast
        var result: [Point] = []
        for ex in exercises {
            for we in ex.workoutExercises {
                guard let w = we.workout, w.userId == userId, let done = w.completedAt, done >= cutoff else { continue }
                let working = we.sets.filter { $0.weight > 0 }
                guard let top = working.max(by: { $0.weight < $1.weight }) else { continue }
                result.append(Point(exercise: ex.name, date: done, topWeight: top.weight))
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// 記録の多い順の種目名（凡例と色割当の順序）。多すぎると読めないので上位 5 種目。
    private var displayedExercises: [String] {
        var counts: [String: Int] = [:]
        for p in points { counts[p.exercise, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(5).map(\.key)
    }

    private var shownPoints: [Point] {
        let names = Set(displayedExercises)
        return points.filter { names.contains($0.exercise) }
    }

    /// 系列色。分析画面の既存パレットを流用して他のグラフと色の意味を揃える。
    private static let palette: [Color] = [Theme.energy, Theme.info, Theme.series2, Theme.warning, Theme.danger]
    private func color(for exercise: String) -> Color {
        let i = displayedExercises.firstIndex(of: exercise) ?? 0
        return Self.palette[i % Self.palette.count]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    fatigueCard
                    if shownPoints.count >= 2 {
                        chartCard
                    } else {
                        EmptyStateView(systemImage: "chart.xyaxis.line", title: "推移はまだ出せません",
                                       message: "この部位の種目を2回以上記録すると、重量の推移が出ます。")
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

    private var fatigueCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Circle().fill(BodyMapView.color(for: status.fatigue)).frame(width: 12, height: 12)
                Text(status.level.label).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Spacer()
                if let last = status.lastTrained {
                    Text("最終 \(last.formatted(.dateTime.month().day()))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("記録なし").font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: status.fatigue)
                .tint(BodyMapView.color(for: status.fatigue))
            Text(caption)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .gymneeCard()
    }

    private var caption: String {
        switch status.level {
        case .recovered:
            return status.lastTrained == nil
                ? "まだこの部位の記録がありません。"
                : "回復済み。次に鍛える候補です。"
        case .recovering:
            return "回復中。軽めなら問題ありませんが、追い込むのは少し待つのが無難です。"
        case .fatigued:
            return "直近\(status.lastSetCount)セット。しっかり休ませたほうが伸びます。"
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "重量の推移（直近6ヶ月・トップセット）")
            Chart(shownPoints) { p in
                LineMark(x: .value("日付", p.date), y: .value("重量", p.topWeight))
                    .foregroundStyle(color(for: p.exercise))
                    .symbol(by: .value("種目", p.exercise))
                PointMark(x: .value("日付", p.date), y: .value("重量", p.topWeight))
                    .foregroundStyle(color(for: p.exercise))
            }
            .chartForegroundStyleScale(domain: displayedExercises, range: displayedExercises.map(color(for:)))
            .chartLegend(.hidden)
            .chartYAxisLabel("kg")
            .frame(height: 200)
            legend
        }
        .gymneeCard()
    }

    private var legend: some View {
        FlowLayout(spacing: Theme.Spacing.sm) {
            ForEach(displayedExercises, id: \.self) { name in
                HStack(spacing: 5) {
                    Circle().fill(color(for: name)).frame(width: 8, height: 8)
                    Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
