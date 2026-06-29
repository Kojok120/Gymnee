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

    private enum Route: Hashable { case history }

    init(userId: UUID) {
        self.userId = userId
        // 最大表示期間(1年=52週)＋バッファ分だけ取得し、多年履歴の全ロードを避ける。
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -53, to: Date()) ?? .distantPast
        _workouts = Query(filter: #Predicate<Workout> { $0.userId == userId && $0.date >= cutoff }, sort: \Workout.date)
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId && $0.visitedAt >= cutoff }, sort: \Visit.visitedAt)
        _prs = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId && $0.achievedAt >= cutoff }, sort: \PersonalRecord.achievedAt, order: .reverse)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                historyLink
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .history: HistoryView(userId: userId)
            }
        }
    }

    /// 集計の手前に置く「記録を一覧で見る」導線（日付/種目ごとの履歴へ）。
    private var historyLink: some View {
        NavigationLink(value: Route.history) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title2).foregroundStyle(Theme.lime)
                    .frame(width: 52, height: 52)
                    .background(Theme.lime.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("記録を一覧で見る").font(.headline).foregroundStyle(Theme.textPrimary)
                    Text("日付・種目ごとの履歴").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .gymneeCard()
        }
        .buttonStyle(.plain)
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
            SectionHeader(title: "来店ヒートマップ（直近\(period.label)）")
            HeatmapView(counts: visitCounts, weeks: period.weeks)
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
                    BarMark(x: .value("週", item.weekStart, unit: .weekOfYear), y: .value("日数", item.count))
                        .foregroundStyle(Theme.energy)
                }
                .chartYScale(domain: 0...7)   // 1週間＝最大7日。
                .chartYAxis { AxisMarks(values: Array(0...7)) }
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
            // 頻度＝その週にトレーニングした「日数」（最大7。1日に複数回でも1日）。
            let days = Set(
                workouts.filter { $0.completedAt != nil && interval.contains($0.date) }
                    .map { calendar.startOfDay(for: $0.date) }
            )
            return WeeklyCount(weekStart: start, count: min(days.count, 7))
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
                    .filter { $0.weight > 0 && $0.reps > 0 }
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
            SectionHeader(title: "自己ベストの記録")
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
        pr.type.formatted(pr.value)
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
                    Text(status.muscle.label)
                        .frame(minWidth: 48, alignment: .leading)
                        .lineLimit(1).minimumScaleFactor(0.7).fixedSize(horizontal: true, vertical: false)
                    ProgressView(value: status.recoveryProgress)
                        .tint(status.isRecovered ? Theme.energy : .orange)
                    Text(status.isRecovered ? "回復" : "回復中")
                        .font(.caption2)
                        .foregroundStyle(status.isRecovered ? Theme.energy : .orange)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }
                .font(.caption)
            }
            // 分析→行動の循環を閉じる：回復済みの部位を踏まえて記録を開始。
            Button {
                NotificationCenter.default.post(name: .gymneeOpenDestination, object: nil, userInfo: ["type": "workout"])
            } label: {
                Label("記録を開始", systemImage: "plus.circle.fill").font(.subheadline.bold())
            }
            .buttonStyle(.borderedProminent).tint(Theme.lime).controlSize(.small)
            .padding(.top, Theme.Spacing.xs)
        }
        .gymneeCard()
    }

    private var recoveryStatuses: [RecoveryAnalyzer.MuscleStatus] {
        var lastTrained: [MuscleGroup: Date] = [:]
        for w in workouts where w.completedAt != nil {
            for we in w.exercises {
                guard let mg = we.exercise?.muscleGroup else { continue }
                if !we.sets.isEmpty {
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
                    entries.append(.init(muscleGroup: mg, weight: set.weight, reps: set.reps, date: w.date))
                }
            }
        }
        return entries
    }
}
