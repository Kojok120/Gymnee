import SwiftUI
import SwiftData

/// 分析タブ。**人体図 1 枚**に絞る。
///
/// 以前はヒートマップ / 強度進捗 / 部位バランス / リカバリー / PRタイムライン / CSV の 6 カードが
/// 縦積みで、情報は多いのに「で、自分はいまどうなのか」が一目で分からなかった。
/// いま見たいのは「どこが疲れていて、次はどこをやるか」なので、人体図 1 枚（正面 / 背面は反転）に集約し、
/// 数値の深掘りは部位タップの先へ送る。CSV は設定へ、PR は種目詳細へ移設した。
struct AnalyticsView: View {
    let userId: UUID

    @Query private var workouts: [Workout]
    @Query private var metrics: [BodyMetric]

    /// タップで開く部位詳細。
    @State private var selectedMuscle: MuscleGroup?
    @State private var showBodyMetrics = false
    @State private var showAddMetric = false
    /// 表示中の面。タブを離れるたび正面に戻らないよう保存する。
    @AppStorage("gymnee.analytics.bodyFace") private var face: BodyMapPaths.Face = .front

    init(userId: UUID) {
        self.userId = userId
        // 疲労度は直近の記録だけで決まる（最長の推奨回復時間 72h）。3ヶ月あれば十分。
        let cutoff = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? .distantPast
        _workouts = Query(
            filter: #Predicate<Workout> { $0.userId == userId && $0.completedAt != nil && $0.date >= cutoff },
            sort: \Workout.date, order: .reverse
        )
        _metrics = Query(filter: #Predicate<BodyMetric> { $0.userId == userId }, sort: \BodyMetric.date, order: .reverse)
    }

    // MARK: - 導出

    /// 完了ワークアウト → 部位ごとのセッション（MuscleFatigue の入力）。
    /// 日付は `completedAt` に一本化する（旧実装は画面ごとに `date` / `completedAt` がズレていた）。
    private var sessionEntries: [MuscleFatigue.SessionEntry] {
        var result: [MuscleFatigue.SessionEntry] = []
        for w in workouts {
            guard let done = w.completedAt else { continue }
            // 同一ワークアウト内の同じ部位はセット数を合算する。
            var setsByMuscle: [MuscleGroup: Int] = [:]
            for we in w.exercises {
                guard let muscle = we.exercise?.muscleGroup, !we.sets.isEmpty else { continue }
                setsByMuscle[muscle, default: 0] += we.sets.count
            }
            for (muscle, count) in setsByMuscle {
                result.append(MuscleFatigue.SessionEntry(muscle: muscle, completedAt: done, setCount: count))
            }
        }
        return result
    }

    private var statuses: [MuscleFatigue.Status] { MuscleFatigue.statuses(entries: sessionEntries) }

    private var fatigueByMuscle: [MuscleGroup: Double] {
        Dictionary(statuses.map { ($0.muscle, $0.fatigue) }, uniquingKeysWith: { a, _ in a })
    }

    private func status(for muscle: MuscleGroup) -> MuscleFatigue.Status {
        statuses.first { $0.muscle == muscle }
            ?? MuscleFatigue.Status(muscle: muscle, lastTrained: nil, lastSetCount: 0, fatigue: 0)
    }

    private var latestWeight: Double? { metrics.first(where: { $0.weight != nil })?.weight }
    private var latestBodyFat: Double? { metrics.first(where: { $0.bodyFat != nil })?.bodyFat }

    // MARK: - 画面

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                bodyCard
                bodyMetricsRow
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.bg0)
        .navigationTitle("分析")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedMuscle) { muscle in
            MuscleDetailSheet(muscle: muscle, userId: userId, status: status(for: muscle))
        }
        .sheet(isPresented: $showBodyMetrics) {
            NavigationStack {
                BodyMetricsView(userId: userId)
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("閉じる") { showBodyMetrics = false } } }
            }
        }
        .sheet(isPresented: $showAddMetric) { AddBodyMetricView(userId: userId) }
    }

    /// 人体図は **1 体だけ**表示し、正面 / 背面は反転で切り替える。
    ///
    /// 2 体並べると 1 体あたりの幅がカードの半分になり、腕・体幹のような細い部位が
    /// タップしづらく色も読み取りにくかった。浮いた横幅をそのまま図の拡大に充てる。
    /// 背面にしかない部位（背中・臀部・ハム）は反転して見る。
    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.xs) {
                BodyMapView(
                    face: face,
                    fatigueByMuscle: fatigueByMuscle,
                    selected: selectedMuscle,
                    onSelect: { selectedMuscle = $0 }
                )
                // 面ごとに別ビューとして扱い、切り替えをクロスフェードさせる。
                // 3D フリップは両面を同時に描く必要があり（パス構築が倍）、
                // 回転中のタップ座標の扱いも読みにくいので採らない。
                .transition(.opacity)
                .id(face)
                // 画面が小さい端末（SE 等）で図がカードを占有しないよう、表示領域に対する上限も掛ける。
                .containerRelativeFrame(.vertical) { height, _ in min(Self.bodyHeight, height * 0.68) }
                .frame(maxWidth: .infinity)
                // 図の外側に重ねる。BodyMapView 内のタップ判定には触らない。
                .overlay(alignment: .topTrailing) { flipButton }
                // 「裏返す」動作として左右スワイプでも切り替える（ボタンの発見性を補う）。
                // `gesture` だと ScrollView のスクロールを奪って図の上で縦に流せなくなるため
                // `simultaneousGesture` にし、縦優位のドラッグ（＝スクロール）では反転しない。
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            flip()
                        }
                )
                // 現在どちらを見ているかはアイコンだけでは読めないので、面のラベルを残す。
                Text(face.label).font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            BodyMapLegend()
            Text(hintText)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .gymneeCard()
    }

    /// 人体図の高さの上限。全幅まで伸ばすと凡例・ヒント・体重タイルが画面外に出るため、
    /// スクロールがほとんど発生しない範囲での最大値に置く。
    private static let bodyHeight: CGFloat = 470

    /// 正面 / 背面の反転ボタン。正面と背面は ON/OFF ではないのでトグルにはしない。
    private var flipButton: some View {
        Button(action: flip) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 36, height: 36)
                .background(Theme.bg2, in: Circle())
                // カード面（bg1）との差が小さいので、縁で押せることを示す。
                .overlay(Circle().stroke(Theme.textTertiary.opacity(0.35), lineWidth: 0.8))
                .frame(width: 44, height: 44)   // タップ領域は 44pt 確保する
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(face == .front ? "背面を表示" : "正面を表示")
    }

    private func flip() {
        withAnimation(.snappy) { face = face == .front ? .back : .front }
    }

    /// 図の下の一言。色を見せて終わりにせず「次にどこをやるか」まで踏み込む。
    private var hintText: String {
        guard !sessionEntries.isEmpty else {
            return "記録をつけると、鍛えた部位が疲労度で色分けされます。部位をタップすると重量の推移が見られます。"
        }
        let ready = MuscleFatigue.recommendedNext(from: statuses)
        guard let first = ready.first else {
            return "全体的に疲労が残っています。今日はしっかり休むのも選択肢です。"
        }
        return "回復済み：\(ready.prefix(3).map(\.label).joined(separator: "・"))。次は\(first.label)が狙い目です。"
    }

    /// 体重・体脂肪率。未記録なら入力画面、記録済みなら推移画面へ（初回のつまずきを作らない）。
    private var bodyMetricsRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            metricTile(label: "体重", value: latestWeight.map { "\(SetFormatting.weightString($0)) kg" },
                       systemImage: "scalemass")
            metricTile(label: "体脂肪率", value: latestBodyFat.map { String(format: "%.1f %%", $0) },
                       systemImage: "percent")
        }
    }

    private func metricTile(label: String, value: String?, systemImage: String) -> some View {
        Button {
            if value == nil { showAddMetric = true } else { showBodyMetrics = true }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(label, systemImage: systemImage)
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                Text(value ?? "記録する")
                    .font(value == nil ? .subheadline.weight(.semibold) : .numS)
                    .foregroundStyle(value == nil ? Theme.lime : Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// `sheet(item:)` に渡すため（`MuscleGroup` 自体は Identifiable ではない）。
extension MuscleGroup: @retroactive Identifiable {
    public var id: String { rawValue }
}
