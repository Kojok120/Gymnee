import SwiftUI
import SwiftData
import UIKit

// MARK: - 集計（純粋ロジック・テスト対象）

/// まとめの対象期間（年間 Wrapped ／ 月次リキャップ）。
enum WrappedPeriod: Equatable, Identifiable {
    case year(Int)
    case month(year: Int, month: Int)

    var id: String { badge }

    /// 期間の実区間（[start, end)。end は次期間の開始）。
    func interval(calendar: Calendar = .current) -> DateInterval {
        let (component, comps): (Calendar.Component, DateComponents) = switch self {
        case .year(let y): (.year, DateComponents(year: y))
        case .month(let y, let m): (.month, DateComponents(year: y, month: m))
        }
        let start = calendar.date(from: comps) ?? .distantPast
        return calendar.dateInterval(of: component, for: start) ?? DateInterval(start: start, duration: 0)
    }

    /// カード右上のバッジ（例: "2026" / "2026.06"）。
    var badge: String {
        switch self {
        case .year(let y): String(y)
        case .month(let y, let m): String(format: "%d.%02d", y, m)
        }
    }

    /// カードの挙上量見出し。
    var volumeTitle: String {
        switch self {
        case .year: "今年の挙上量"
        case .month(_, let m): "\(m)月の挙上量"
        }
    }

    /// 画面タイトル。
    var navTitle: String {
        switch self {
        case .year(let y): "\(y) Wrapped"
        case .month(let y, let m): "\(y)年\(m)月のまとめ"
        }
    }

    /// 先月（月次リキャップの既定対象）。
    static func previousMonth(from date: Date = .now, calendar: Calendar = .current) -> WrappedPeriod {
        let prev = calendar.date(byAdding: .month, value: -1, to: date) ?? date
        return .month(year: calendar.component(.year, from: prev),
                      month: calendar.component(.month, from: prev))
    }
}

/// 期間の総括統計（④ Gymnee Wrapped / 月次リキャップ）。記録から「その期間の自分」を 1 画面に凝縮する。
struct WrappedStats: Equatable {
    var period: WrappedPeriod
    var workoutCount: Int
    var totalSets: Int
    var totalVolume: Int        // kg
    var prCount: Int
    var visitCount: Int
    var activeWeeks: Int        // トレした週数
    var topExerciseName: String?
    var topExerciseCount: Int
    var topMuscle: MuscleGroup?

    /// 総挙上量を身近な比喩に（普通車 ≒ 1.5t 換算）。「車◯台分を持ち上げた」。
    var carEquivalent: Double { Double(totalVolume) / 1500.0 }
    var hasData: Bool { workoutCount > 0 || visitCount > 0 }

    static func compute(
        workouts: [Workout],
        personalRecords: [PersonalRecord],
        visits: [Visit],
        period: WrappedPeriod,
        calendar: Calendar = .current
    ) -> WrappedStats {
        let interval = period.interval(calendar: calendar)
        func inPeriod(_ d: Date) -> Bool { d >= interval.start && d < interval.end }
        func weekKey(_ d: Date) -> Date? { calendar.dateInterval(of: .weekOfYear, for: d)?.start }

        let periodWorkouts = workouts.filter { w in
            guard let done = w.completedAt else { return false }
            return inPeriod(done)
        }
        let sets = periodWorkouts.flatMap { $0.exercises.flatMap(\.sets) }
        let vol = sets.reduce(0.0) { $0 + $1.volume }
        let totalVolume = vol.isFinite ? Int(vol) : 0
        let prCount = personalRecords.filter { inPeriod($0.achievedAt) }.count
        let periodVisits = visits.filter { inPeriod($0.visitedAt) }

        // 最多種目（期間内で記録した回数）。
        var exCount: [String: Int] = [:]
        var muscleCount: [MuscleGroup: Int] = [:]
        for w in periodWorkouts {
            for we in w.exercises {
                guard let ex = we.exercise else { continue }
                exCount[ex.name, default: 0] += 1
                muscleCount[ex.muscleGroup, default: 0] += 1
            }
        }
        let topEx = exCount.max { $0.value < $1.value }
        let topMuscle = muscleCount.max { $0.value < $1.value }?.key

        // トレした週数（ワークアウト完了日＋来店日）。
        var weeks = Set<Date>()
        for w in periodWorkouts { if let k = (w.completedAt).flatMap(weekKey) { weeks.insert(k) } }
        for v in periodVisits { if let k = weekKey(v.visitedAt) { weeks.insert(k) } }

        return WrappedStats(
            period: period,
            workoutCount: periodWorkouts.count,
            totalSets: sets.count,
            totalVolume: totalVolume,
            prCount: prCount,
            visitCount: periodVisits.count,
            activeWeeks: weeks.count,
            topExerciseName: topEx?.key,
            topExerciseCount: topEx?.value ?? 0,
            topMuscle: topMuscle
        )
    }
}

// MARK: - 画面

/// 期間総括（年間 Gymnee Wrapped ／ 月次リキャップ）。Spotify Wrapped 的に「その期間の自分」を見せ、
/// ブランドカードで共有させる。
struct GymneeWrappedView: View {
    let userId: UUID
    let period: WrappedPeriod
    var onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var workouts: [Workout]
    @Query private var prs: [PersonalRecord]
    @Query private var visits: [Visit]

    @State private var rendered: UIImage?
    @State private var saveMessage: String?

    init(userId: UUID,
         period: WrappedPeriod = .year(Calendar.current.component(.year, from: .now)),
         onClose: @escaping () -> Void) {
        self.userId = userId
        self.period = period
        self.onClose = onClose
        _workouts = Query(filter: #Predicate<Workout> { $0.userId == userId })
        _prs = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId })
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId })
    }

    private var stats: WrappedStats {
        WrappedStats.compute(workouts: workouts, personalRecords: prs, visits: visits, period: period)
    }

    var body: some View {
        // stats（全セット走査＋集計）は計算プロパティのため、1回の body 評価で束ねて再計算を避ける。
        let stats = self.stats
        return NavigationStack {
            ScrollView {
                if stats.hasData {
                    VStack(spacing: Theme.Spacing.lg) {
                        WrappedShareCard(stats: stats, side: 320)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                            .shadow(radius: 10)
                        statGrid(stats)
                        shareActions
                    }
                    .padding(Theme.Spacing.lg)
                } else {
                    EmptyStateView(systemImage: "sparkles",
                                   title: "\(period.navTitle) はまだ作れません",
                                   message: "ワークアウトを記録すると、この期間の総挙上量やPRがここに集まります。")
                        .padding(.top, 80)
                }
            }
            .background(Theme.bg0)
            .navigationTitle(period.navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { onClose() } }
            }
            .onAppear { rerender() }
            .alert(saveMessage ?? "", isPresented: Binding(get: { saveMessage != nil }, set: { if !$0 { saveMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func statGrid(_ stats: WrappedStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
            StatPill(value: "\(stats.totalVolume)", label: "総挙上量 kg", tint: Theme.lime, systemImage: "scalemass.fill")
            StatPill(value: "\(stats.workoutCount)", label: "ワークアウト", tint: Theme.textPrimary, systemImage: "dumbbell.fill")
            StatPill(value: "\(stats.prCount)", label: "自己ベスト", tint: Theme.warning, systemImage: "trophy.fill")
            StatPill(value: "\(stats.activeWeeks)", label: "活動週", tint: Theme.info, systemImage: "calendar")
        }
    }

    private var shareActions: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let rendered {
                ShareLink(item: Image(uiImage: rendered), preview: SharePreview("Gymnee \(stats.period.navTitle)", image: Image(uiImage: rendered))) {
                    Label("まとめを共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent).prominentLime()
                Button {
                    UIImageWriteToSavedPhotosAlbum(rendered, nil, nil, nil)
                    saveMessage = "写真に保存しました"
                } label: {
                    Label("写真に保存", systemImage: "photo.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                ProgressView()
            }
        }
    }

    @MainActor private func rerender() {
        let card = WrappedShareCard(stats: stats, side: 360)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        rendered = renderer.uiImage
    }
}

// MARK: - 共有カード

/// Wrapped の共有用ブランドカード（ダーク＋lime）。SNS 拡散＝無料の獲得チャネル。
struct WrappedShareCard: View {
    let stats: WrappedStats
    var side: CGFloat = 360

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hexF: 0x0B0D0C), Color(hexF: 0x141A12), Color(hexF: 0x1E2A12)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: side * 0.03) {
                HStack {
                    Label("Gymnee", systemImage: "figure.strengthtraining.traditional")
                        .font(.system(size: side * 0.052, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.lime)
                    Spacer()
                    Text(stats.period.badge).font(.system(size: side * 0.05, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Text(stats.period.volumeTitle)
                    .font(.system(size: side * 0.04, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("\(stats.totalVolume) kg")
                    .font(.system(size: side * 0.11, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.lime)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if stats.carEquivalent >= 1 {
                    Label("車 \(String(format: "%.0f", stats.carEquivalent)) 台分を持ち上げた💪", systemImage: "car.fill")
                        .font(.system(size: side * 0.036, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer(minLength: 0)
                HStack(spacing: side * 0.03) {
                    miniStat("\(stats.workoutCount)", "回")
                    miniStat("\(stats.prCount)", "PR")
                    miniStat("\(stats.activeWeeks)", "週")
                }
                if let ex = stats.topExerciseName {
                    Text("最多種目 · \(ex)")
                        .font(.system(size: side * 0.034, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .padding(side * 0.06)
        }
        .frame(width: side, height: side)
        .clipped()
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: side * 0.06, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            Text(label).font(.system(size: side * 0.03, weight: .semibold))
                .foregroundStyle(Theme.lime)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, side * 0.025)
        .padding(.horizontal, side * 0.03)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: side * 0.03, style: .continuous))
    }
}
