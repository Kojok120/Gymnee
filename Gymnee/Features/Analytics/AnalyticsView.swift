import SwiftUI
import SwiftData
import Charts

/// 分析ダッシュボード（§6.8）。頻度・部位バランス・リカバリービュー・ヒートマップ・強度進捗・CSV。
struct AnalyticsView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Query private var workouts: [Workout]
    @Query private var visits: [Visit]
    @State private var csvURL: URL?

    private let calendar = Calendar.current

    init(userId: UUID) {
        self.userId = userId
        _workouts = Query(filter: #Predicate<Workout> { $0.userId == userId }, sort: \Workout.date)
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId }, sort: \Visit.visitedAt)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                heatmapCard
                frequencyCard
                balanceCard
                recoveryCard
                exportCard
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("分析")
        .navigationBarTitleDisplayMode(.inline)
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
            SectionHeader(title: "週次頻度（直近12週）")
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
        return (0..<12).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: start) else { return nil }
            let count = workouts.filter { $0.completedAt != nil && interval.contains($0.date) }.count
            return WeeklyCount(weekStart: start, count: count)
        }
    }

    // MARK: - Muscle balance

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "部位バランス（直近4週・セット数）")
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
        let entries = recentVolumeEntries(weeks: 4)
        let counts = VolumeCalculator.setCountByMuscle(entries)
        let muscles = RecoveryAnalyzer.trackedMuscles
        let maxCount = max(muscles.map { Double(counts[$0] ?? 0) }.max() ?? 1, 1)
        return muscles.map { mg in
            let v = Double(counts[mg] ?? 0)
            return Balance(label: mg.label, value: v, normalized: v / maxCount)
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
