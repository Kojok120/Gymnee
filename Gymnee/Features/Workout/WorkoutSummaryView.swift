import SwiftUI
import SwiftData

/// ワークアウト完了サマリー（達成レイヤー / 監査T1a）。
/// 「やり切った瞬間」を無音で終わらせず、総ボリューム/セット/時間/PRを祝い、
/// 共有・分析・閉じるの次アクションへ分岐させる。
struct WorkoutSummaryView: View {
    let workout: Workout
    let streak: Int
    var onShare: () -> Void
    var onAnalytics: () -> Void
    var onClose: () -> Void

    private var workingSets: [ExerciseSet] {
        workout.exercises.flatMap(\.sets)
    }
    private var totalVolume: Int {
        let v = workingSets.reduce(0) { $0 + $1.volume }
        return v.isFinite ? Int(v) : 0   // 非有限混入時も Int(∞) でトラップしない
    }
    private var totalSets: Int { workingSets.count }
    private var exerciseCount: Int { workout.exercises.count }
    /// このワークアウトで更新した PR を種目ごとにまとめる（種類ラベルを PRType.allCases 順で連結）。
    /// 完了時に upsertPR が PersonalRecord.workoutId = workout.id をセットするのを利用する。
    private var prItems: [(name: String, types: String)] {
        let wid = workout.id
        return workout.exercises.compactMap { we in
            guard let ex = we.exercise else { return nil }
            let labels = PRType.allCases
                .filter { t in ex.personalRecords.contains { $0.workoutId == wid && $0.typeRaw == t.rawValue } }
                .map(\.label)
            return labels.isEmpty ? nil : (ex.name, labels.joined(separator: "・"))
        }
    }
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
                    statGrid
                    if !prItems.isEmpty { prCard }
                    actions
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("完了！")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { onClose() } }
            }
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.lime)
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

    private var prCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("自己ベスト更新！", systemImage: "medal.fill")
                .font(.subheadline.bold()).foregroundStyle(Theme.lime)
            ForEach(prItems, id: \.name) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.caption.bold()).foregroundStyle(Theme.textPrimary)
                    Text(item.types).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.limeSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button { onShare() } label: {
                Label("共有する", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
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
