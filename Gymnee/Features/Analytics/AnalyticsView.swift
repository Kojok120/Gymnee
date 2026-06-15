import SwiftUI
import SwiftData
import Charts

/// 分析ダッシュボード（§6.8）。頻度・部位バランス・リカバリービュー・ヒートマップ・強度進捗・CSV。
struct AnalyticsView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Query private var workouts: [Workout]
    @Query private var visits: [Visit]
    @Query private var prs: [PersonalRecord]
    @State private var csvURL: URL?
    @State private var period: Period = .quarter

    private let calendar = Calendar.current

    enum Period: String, CaseIterable, Identifiable {
        case month, quarter, year
        var id: String { rawValue }
        var label: String { self == .month ? "4週" : self == .quarter ? "12週" : "1年" }
        var weeks: Int { self == .month ? 4 : self == .quarter ? 12 : 52 }
    }

    init(userId: UUID) {
        self.userId = userId
        _workouts = Query(filter: #Predicate<Workout> { $0.userId == userId }, sort: \Workout.date)
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId }, sort: \Visit.visitedAt)
        _prs = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId }, sort: \PersonalRecord.achievedAt, order: .reverse)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                periodPicker
                heatmapCard
                frequencyCard
                strengthCard
                balanceCard
                recoveryCard
                prTimelineCard
                exportCard
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("分析")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var periodPicker: some View {
        Picker("期間", selection: $period) {
            ForEach(Period.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var periodStart: Date {
        calendar.date(byAdding: .weekOfYear, value: -period.weeks, to: .now) ?? .distantPast
    }

    // MARK: - Heatmap

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "来店ヒートマップ")
            HeatmapView(counts: visitCounts)
        }
        .gymneeCard()
    }

    private var visitCounts: [Date: Int] {
        var counts: [Date: Int] = [:]
        for v in visits { counts[calendar.startOfDay(for: v.visitedAt), default: 0] += 1 }
        return counts
    }

    // MARK: - Frequency

    private var frequencyCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "週次頻度（直近\(period.label)）")
            if weeklyCounts.allSatisfy({ $0.count == 0 }) {
                Text("記録が増えると表示されます。").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(weeklyCounts, id: \.weekStart) { item in
                    BarMark(x: .value("週", item.weekStart, unit: .weekOfYear), y: .value("回数", item.count))
                        .foregroundStyle(Theme.energy)
                }
                .frame(height: 160)
            }
        }
        .gymneeCard()
    }

    private struct WeeklyCount { let weekStart: Date; let count: Int }
    private var weeklyCounts: [WeeklyCount] {
        let today = calendar.startOfDay(for: .now)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<period.weeks).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: start) else { return nil }
            let count = workouts.filter { $0.completedAt != nil && interval.contains($0.date) }.count
            return WeeklyCount(weekStart: start, count: count)
        }
    }

    // MARK: - Muscle balance

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "部位バランス（直近\(period.label)・セット数）")
            if balanceData.allSatisfy({ $0.value == 0 }) {
                Text("ワークアウトを記録すると表示されます。").font(.caption).foregroundStyle(.secondary)
            } else {
                RadarChartView(data: balanceData.map { ($0.label, $0.normalized, "\(Int($0.value))") })
                    .frame(height: 240)
            }
        }
        .gymneeCard()
    }

    private struct Balance { let label: String; let value: Double; let normalized: Double }
    private var balanceData: [Balance] {
        let entries = recentVolumeEntries(weeks: period.weeks)
        let counts = VolumeCalculator.setCountByMuscle(entries)
        let muscles = RecoveryAnalyzer.trackedMuscles
        let maxCount = max(muscles.map { Double(counts[$0] ?? 0) }.max() ?? 1, 1)
        return muscles.map { mg in
            let v = Double(counts[mg] ?? 0)
            return Balance(label: mg.label, value: v, normalized: v / maxCount)
        }
    }

    // MARK: - Strength progress

    private var strengthCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "強度進捗（推定1RM）")
            if strengthPoints.isEmpty {
                Text("ワークアウトを重ねると主要種目の推移が出ます。").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(strengthPoints) { p in
                    LineMark(x: .value("日付", p.date), y: .value("推定1RM", p.e1RM))
                        .foregroundStyle(by: .value("種目", p.exercise))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("日付", p.date), y: .value("推定1RM", p.e1RM))
                        .foregroundStyle(by: .value("種目", p.exercise))
                }
                .chartYAxisLabel("kg")
                .frame(height: 200)
            }
        }
        .gymneeCard()
    }

    private struct StrengthPoint: Identifiable {
        let id = UUID(); let date: Date; let e1RM: Double; let exercise: String
    }

    /// 期間内で最も頻度の高い上位3種目の推定1RM推移。
    private var strengthPoints: [StrengthPoint] {
        let start = periodStart
        // 期間内の (種目 -> [WorkoutExercise]) を集計。
        var byExercise: [String: [WorkoutExercise]] = [:]
        for w in workouts where w.completedAt != nil && w.date >= start {
            for we in w.exercises {
                guard let name = we.exercise?.name else { continue }
                byExercise[name, default: []].append(we)
            }
        }
        let top = byExercise.sorted { $0.value.count > $1.value.count }.prefix(3)
        var points: [StrengthPoint] = []
        for (name, wes) in top {
            for we in wes {
                guard let date = we.workout?.date else { continue }
                let best = we.sets
                    .filter { $0.type != .warmup && $0.weight > 0 && $0.reps > 0 }
                    .map { OneRepMax.estimate(weight: $0.weight, reps: $0.reps) }
                    .max()
                if let best { points.append(StrengthPoint(date: date, e1RM: best, exercise: name)) }
            }
        }
        return points.sorted { $0.date < $1.date }
    }

    // MARK: - PR timeline

    private var prTimelineCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "PR タイムライン")
            let recent = prs.filter { $0.achievedAt >= periodStart }
            if recent.isEmpty {
                Text("この期間の自己ベスト更新はありません。").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(recent.prefix(12)) { pr in
                    HStack {
                        Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(pr.exercise?.name ?? "種目") · \(pr.type.label)").font(.subheadline)
                            Text(pr.achievedAt, format: .dateTime.year().month().day())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(prValue(pr)).font(.subheadline.bold())
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .gymneeCard()
    }

    private func prValue(_ pr: PersonalRecord) -> String {
        switch pr.type {
        case .maxReps: return "\(Int(pr.value)) reps"
        case .maxVolume: return String(format: "%.0f kg", pr.value)
        default: return String(format: "%.1f kg", pr.value)
        }
    }

    // MARK: - Recovery

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "リカバリー")
            let statuses = recoveryStatuses
            let next = RecoveryAnalyzer.recommendedNext(from: statuses).prefix(3)
            if !next.isEmpty {
                Text("次の候補: " + next.map(\.label).joined(separator: "・"))
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.energy)
            }
            ForEach(statuses) { status in
                HStack {
                    Text(status.muscle.label).frame(width: 48, alignment: .leading)
                    ProgressView(value: status.recoveryProgress)
                        .tint(status.isRecovered ? Theme.energy : .orange)
                    Text(status.isRecovered ? "回復" : "回復中")
                        .font(.caption2)
                        .foregroundStyle(status.isRecovered ? Theme.energy : .orange)
                        .frame(width: 40)
                }
                .font(.caption)
            }
        }
        .gymneeCard()
    }

    private var recoveryStatuses: [RecoveryAnalyzer.MuscleStatus] {
        var lastTrained: [MuscleGroup: Date] = [:]
        for w in workouts where w.completedAt != nil {
            for we in w.exercises {
                guard let mg = we.exercise?.muscleGroup else { continue }
                if we.sets.contains(where: { $0.type != .warmup }) {
                    if let existing = lastTrained[mg] { lastTrained[mg] = max(existing, w.date) }
                    else { lastTrained[mg] = w.date }
                }
            }
        }
        return RecoveryAnalyzer.statuses(lastTrained: lastTrained)
    }

    // MARK: - Export

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "データエクスポート")
            Text("全記録を CSV で書き出せます（データ所有権）。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button {
                    csvURL = CSVExporter.writeTempFile(CSVExporter.workoutsCSV(userId: userId, context: context), name: "gymnee_workouts")
                } label: { Label("ワークアウト", systemImage: "square.and.arrow.up").font(.caption) }
                    .buttonStyle(.bordered)
                Button {
                    csvURL = CSVExporter.writeTempFile(CSVExporter.visitsCSV(userId: userId, context: context), name: "gymnee_visits")
                } label: { Label("来店", systemImage: "square.and.arrow.up").font(.caption) }
                    .buttonStyle(.bordered)
            }
            if let csvURL {
                ShareLink(item: csvURL) { Label("共有: \(csvURL.lastPathComponent)", systemImage: "doc") .font(.caption) }
            }
        }
        .gymneeCard()
    }

    // MARK: - Shared volume entries

    private func recentVolumeEntries(weeks: Int) -> [VolumeCalculator.VolumeEntry] {
        let cutoff = calendar.date(byAdding: .weekOfYear, value: -weeks, to: .now) ?? .distantPast
        var entries: [VolumeCalculator.VolumeEntry] = []
        for w in workouts where w.completedAt != nil && w.date >= cutoff {
            for we in w.exercises {
                guard let mg = we.exercise?.muscleGroup else { continue }
                for set in we.sets {
                    entries.append(.init(muscleGroup: mg, weight: set.weight, reps: set.reps, type: set.type, date: w.date))
                }
            }
        }
        return entries
    }
}
