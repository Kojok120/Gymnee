import SwiftUI
import SwiftData

/// ワークアウト完了サマリー（達成レイヤー / 監査T1a）。
/// 「やり切った瞬間」を無音で終わらせず、総ボリューム/セット/時間/PRを祝い、
/// 共有・分析・閉じるの次アクションへ分岐させる。
/// PR を更新した時だけ紙吹雪＋計測タイプ別トロフィーで特別に祝う（普段は静かに完了）。
struct WorkoutSummaryView: View {
    let workout: Workout
    let streak: Int
    var onAnalytics: () -> Void
    var onClose: () -> Void

    @State private var appeared = false
    @State private var showShare = false

    private var workingSets: [ExerciseSet] {
        workout.exercises.flatMap(\.sets)
    }
    private var totalVolume: Int {
        let v = workingSets.reduce(0) { $0 + $1.volume }
        return v.isFinite ? Int(v) : 0   // 非有限混入時も Int(∞) でトラップしない
    }
    private var totalSets: Int { workingSets.count }
    private var exerciseCount: Int { workout.exercises.count }

    /// このワークアウトで更新した PR（種目×計測タイプ）。
    /// 完了時に upsertPR が PersonalRecord.workoutId = workout.id をセットするのを利用する。
    private var prs: [SummaryPR] {
        let wid = workout.id
        return workout.exercises.flatMap { we -> [SummaryPR] in
            guard let ex = we.exercise else { return [] }
            return ex.personalRecords
                .filter { $0.workoutId == wid }
                .compactMap { pr -> SummaryPR? in
                    guard let t = PRType(rawValue: pr.typeRaw) else { return nil }
                    return SummaryPR(exerciseName: ex.name, type: t, value: pr.value)
                }
        }
        .sorted { lhs, rhs in
            let order = PRType.allCases
            return (order.firstIndex(of: lhs.type) ?? 0) < (order.firstIndex(of: rhs.type) ?? 0)
        }
    }
    private var hasPR: Bool { !prs.isEmpty }

    private var durationText: String? {
        guard let end = workout.completedAt else { return nil }
        let mins = max(1, Int(end.timeIntervalSince(workout.date) / 60))
        return "\(mins)分"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    header
                    if hasPR { prTrophies }
                    statGrid
                    actions
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .overlay(alignment: .top) {
                if hasPR && appeared { ConfettiView().transition(.opacity) }
            }
            .navigationTitle(hasPR ? "自己ベスト更新！" : "完了！")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { onClose() } }
            }
            .onAppear { withAnimation(.smooth) { appeared = true } }
            .sensoryFeedback(hasPR ? .success : .impact(weight: .light), trigger: appeared)
            .sheet(isPresented: $showShare) {
                ShareCardEditorView(content: .from(workout: workout, streak: streak > 0 ? streak : nil))
            }
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                if hasPR {
                    Circle()
                        .fill(Theme.celebration)
                        .frame(width: 88, height: 88)
                        .shadow(color: Theme.limeGlow, radius: 20, y: 6)
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Theme.onLime)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.lime)
                }
            }
            .scaleEffect(appeared ? 1 : 0.4)
            .animation(.bouncy, value: appeared)

            Text(workout.name).font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).truncationMode(.tail)
            if streak > 0 {
                Label("\(streak)日連続", systemImage: "flame.fill")
                    .font(.subheadline.bold()).foregroundStyle(Theme.warning)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
    }

    /// 獲得トロフィーの並び。横スクロールで計測タイプ別バッジが順に立ち上がる。
    private var prTrophies: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("獲得トロフィー", systemImage: "medal.fill")
                .font(.subheadline.bold()).foregroundStyle(Theme.lime)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    ForEach(Array(prs.enumerated()), id: \.element.id) { idx, pr in
                        PRTrophyBadge(type: pr.type, value: pr.value, exerciseName: pr.exerciseName, index: idx)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, Theme.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.limeSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.lime.opacity(0.4), lineWidth: 1)
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
            stat("種目", "\(exerciseCount)")
            stat("セット", "\(totalSets)")
            stat("総ボリューム", "\(totalVolume) kg")
            if let d = durationText { stat("所要時間", d) }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.md)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button { showShare = true } label: {
                Label("共有カードを作る", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.lime).controlSize(.large)
            Button { onAnalytics() } label: {
                Label("分析を見る", systemImage: "chart.bar.xaxis").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .padding(.top, Theme.Spacing.sm)
    }
}

/// サマリーで祝う 1 件の PR（種目×計測タイプ×値）。
private struct SummaryPR: Identifiable {
    let exerciseName: String
    let type: PRType
    let value: Double
    var id: String { "\(exerciseName)-\(type.rawValue)" }
}
