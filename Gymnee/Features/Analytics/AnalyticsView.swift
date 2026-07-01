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
    /// 強度進捗グラフに表示する種目（空＝頻度上位5の既定）。シートで増減できる。
    @State private var pinnedExercises: Set<String> = []
    /// 表示種目を選ぶシートの表示。
    @State private var showExercisePicker = false

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

    /// 来店ヒートマップは期間セレクタから切り離し、直近12週の貢献グラフ（幅いっぱい）に固定する。
    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "来店ヒートマップ（直近12週）")
            HeatmapView(counts: visitCounts, weeks: 12, contribution: true)
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
            // 週判定・日付の重複排除とも completedAt 基準に統一（date 基準だと日跨ぎや後完了でズレる）。
            let days = Set(
                workouts.compactMap { workout -> Date? in
                    guard let completedAt = workout.completedAt,
                          interval.contains(completedAt) else { return nil }
                    return calendar.startOfDay(for: completedAt)
                }
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
            if weightedExercisesByFreq.isEmpty {
                Text("ワークアウトを重ねると主要種目の推移が出ます。").font(.caption).foregroundStyle(.secondary)
            } else {
                exerciseSelector
                if strengthPoints.isEmpty {
                    Text("表示する種目を選んでください。").font(.caption).foregroundStyle(.secondary)
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
        }
        .gymneeCard()
    }

    /// 表示種目の選択導線。横スクロールのチップをやめ、検索付きシートで選ぶ。
    private var exerciseSelector: some View {
        Button { showExercisePicker = true } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.energy)
                Text(exerciseSelectionSummary)
                    .font(.subheadline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 10)
            .background(Theme.bg3, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showExercisePicker) {
            StrengthExercisePicker(
                all: weightedExercisesByFreq,
                defaultTop: Array(weightedExercisesByFreq.prefix(5)),
                pinned: $pinnedExercises
            )
        }
    }

    /// 選択サマリ（未選択＝上位Nの既定 / 選択あり＝先頭種目＋件数）。
    private var exerciseSelectionSummary: String {
        let shown = displayedExercises
        if pinnedExercises.isEmpty { return "主要種目（上位\(shown.count)）" }
        if shown.isEmpty { return "種目を選択" }
        if shown.count == 1 { return shown[0] }
        return "\(shown[0]) 他\(shown.count - 1)種目"
    }

    private struct StrengthPoint: Identifiable {
        let id = UUID(); let date: Date; let e1RM: Double; let exercise: String
    }

    /// 期間内の (種目 -> [WorkoutExercise])（完了ワークアウトのみ）。
    private var byExerciseInPeriod: [String: [WorkoutExercise]] {
        let start = periodStart
        var byExercise: [String: [WorkoutExercise]] = [:]
        // 期間判定は週次頻度と揃えて完了時刻(completedAt)基準にする（深夜跨ぎの日ズレ防止）。
        for w in workouts where (w.completedAt ?? .distantPast) >= start {
            for we in w.exercises {
                guard let name = we.exercise?.name else { continue }
                byExercise[name, default: []].append(we)
            }
        }
        return byExercise
    }

    /// 推定1RMが出せる種目（加重セットあり）を頻度の高い順に。グラフ・選択チップの母集合。
    private var weightedExercisesByFreq: [String] {
        byExerciseInPeriod
            .filter { $0.value.contains { we in we.sets.contains { $0.weight > 0 && $0.reps > 0 } } }
            .sorted { a, b in a.value.count != b.value.count ? a.value.count > b.value.count : a.key < b.key }
            .map(\.key)
    }

    /// グラフに表示する種目：選択があればそれ（母集合内のみ）、無ければ頻度上位5。
    private var displayedExercises: [String] {
        let avail = weightedExercisesByFreq
        if pinnedExercises.isEmpty { return Array(avail.prefix(5)) }
        return avail.filter { pinnedExercises.contains($0) }
    }

    /// 表示種目の推定1RM推移（日ごとの最大推定1RM）。
    private var strengthPoints: [StrengthPoint] {
        let by = byExerciseInPeriod
        var points: [StrengthPoint] = []
        for name in displayedExercises {
            for we in by[name] ?? [] {
                // プロット日付も完了時刻基準（週次頻度と同じ）。byExerciseInPeriod で完了済みのみ。
                guard let date = we.workout?.completedAt else { continue }
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

/// 強度進捗グラフに表示する種目を選ぶシート（検索＋チェックの縦リスト）。
/// 横スクロールのチップだと目的の種目を探しづらいため、検索付きの一覧で増減する。
private struct StrengthExercisePicker: View {
    /// 推定1RMを出せる種目（頻度順）。
    let all: [String]
    /// 未選択時の既定（頻度上位N）。
    let defaultTop: [String]
    @Binding var pinned: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    /// 実際に表示中の種目（未選択なら既定の上位N）。
    private var shown: Set<String> { pinned.isEmpty ? Set(defaultTop) : pinned }
    private var filtered: [String] {
        search.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if all.isEmpty {
                    Text("推定1RMを出せる種目がまだありません。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(filtered, id: \.self) { name in
                        Button { toggle(name) } label: {
                            HStack {
                                Text(name).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if shown.contains(name) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.energy).fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "種目を検索")
            .navigationTitle("表示する種目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    /// 初回操作で既定(上位N)を取り込んでから増減する。空にすると既定へ戻る（チップ時と同じ挙動）。
    private func toggle(_ name: String) {
        if pinned.isEmpty { pinned = Set(defaultTop) }
        if pinned.contains(name) { pinned.remove(name) } else { pinned.insert(name) }
    }
}
