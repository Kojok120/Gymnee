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
    /// 部位タップを一度でもしたか（初回ヒントの出し分け）。
    @AppStorage("gymnee.analytics.bodyTapHinted") private var bodyTapHinted = false
    /// 未タップでも数秒で引っ込める（出しっぱなしは邪魔になる）。
    @State private var tapHintVisible = true

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

    /// 完了ワークアウト → 部位ごとのセッション（疲労度・今週の量の共通入力）。
    private var sessionEntries: [MuscleFatigue.SessionEntry] {
        MuscleLoadInputs.sessionEntries(from: workouts)
    }

    private var statuses: [MuscleFatigue.Status] { MuscleFatigue.statuses(entries: sessionEntries) }

    /// 今週の部位別セット数（人体図の塗り）。
    private var weeklyStatuses: [WeeklyMuscleLoad.Status] { WeeklyMuscleLoad.statuses(entries: sessionEntries) }

    private var fatigueByMuscle: [MuscleGroup: Double] {
        Dictionary(statuses.map { ($0.muscle, $0.fatigue) }, uniquingKeysWith: { a, _ in a })
    }

    private var loadByMuscle: [MuscleGroup: Double] {
        Dictionary(weeklyStatuses.map { ($0.muscle, $0.progress) }, uniquingKeysWith: { a, _ in a })
    }

    private func status(for muscle: MuscleGroup) -> MuscleFatigue.Status {
        statuses.first { $0.muscle == muscle }
            ?? MuscleFatigue.Status(muscle: muscle, lastTrained: nil, lastSetCount: 0, fatigue: 0)
    }

    private func weeklyStatus(for muscle: MuscleGroup) -> WeeklyMuscleLoad.Status {
        weeklyStatuses.first { $0.muscle == muscle }
            ?? WeeklyMuscleLoad.Status(muscle: muscle, sets: 0, targetSets: WeeklyMuscleLoad.targetSets(for: muscle))
    }

    private var latestWeight: Double? { metrics.first(where: { $0.weight != nil })?.weight }
    private var latestBodyFat: Double? { metrics.first(where: { $0.bodyFat != nil })?.bodyFat }

    // MARK: - 画面

    var body: some View {
        ScrollView {
            bodyCard
                .padding(Theme.Spacing.lg)
        }
        .background(Theme.bg0)
        .navigationTitle("からだ")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedMuscle) { muscle in
            MuscleDetailSheet(muscle: muscle, userId: userId,
                              status: status(for: muscle), weekly: weeklyStatus(for: muscle))
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
            weekHeader
            VStack(spacing: Theme.Spacing.xs) {
                BodyMapView(
                    face: face,
                    loadByMuscle: loadByMuscle,
                    fatigueByMuscle: fatigueByMuscle,
                    selected: selectedMuscle,
                    onSelect: { muscle in
                        selectedMuscle = muscle
                        // 一度タップできたらヒントの役目は終わり。
                        if !bodyTapHinted { withAnimation(.snappy) { bodyTapHinted = true } }
                    }
                )
                // 面ごとに別ビューとして扱い、切り替えをクロスフェードさせる。
                // 3D フリップは両面を同時に描く必要があり（パス構築が倍）、
                // 回転中のタップ座標の扱いも読みにくいので採らない。
                .transition(.opacity)
                .id(face)
                // 図以外（見出し・面ラベル・凡例・ヒント・余白）が使う分を引いた残りを図に充てる。
                // 割合で抑えると小型端末でだけ溢れるので、固定の実測値を引く形にする。
                .containerRelativeFrame(.vertical) { height, _ in
                    min(Self.bodyHeight, max(Self.bodyHeightFloor, height - Self.bodyCardChrome))
                }
                .frame(maxWidth: .infinity)
                // 図の外側に重ねる。BodyMapView 内のタップ判定には触らない。
                .overlay(alignment: .topTrailing) { flipButton }
                // 体重・体脂肪率は図の左右下に逃がす。図の枠はアスペクト比（0.568）で決まる一方、
                // 脚の高さでは実際のシルエットが枠の 1/3 ほどまで細くなり、左右に必ず余白が残る。
                // カードの外へ別行で置くと 1 画面に収まらず、体重を見るだけでスクロールが要っていた。
                .overlay(alignment: .bottomLeading) {
                    metricTile(label: "体重", value: latestWeight.map { "\(SetFormatting.weightString($0)) kg" },
                               systemImage: "scalemass")
                }
                .overlay(alignment: .bottomTrailing) {
                    metricTile(label: "体脂肪率", value: latestBodyFat.map { String(format: "%.1f %%", $0) },
                               systemImage: "percent")
                }
                .overlay { if showTapHint { tapHint } }
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

    /// 人体図の高さの上限。これ以上伸ばしても図の横幅はアスペクト比でカード幅に頭打ちになり、
    /// 上下に余白が増えるだけなので大型端末ではここで止める。
    private static let bodyHeight: CGFloat = 680

    /// 図が潰れて部位を押せなくなる下限。ここを割るならスクロールさせる。
    private static let bodyHeightFloor: CGFloat = 380

    /// 図の上下でカードが使う高さ（外余白 32 ＋ カード余白 32 ＋ 見出し・面ラベル・凡例・ヒント・行間）。
    /// 体重・体脂肪率は図の上に重ねたのでここには含まれない。
    private static let bodyCardChrome: CGFloat = 175

    private var showTapHint: Bool { !bodyTapHinted && tapHintVisible }

    /// 初回だけ出す「部位を押せる」ヒント。
    /// 図の上に重ねるが `allowsHitTesting(false)` なので、ヒントごしにそのままタップできる。
    private var tapHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 24, weight: .medium))
                .symbolEffect(.pulse)
            Text("部位をタップ").font(.caption.weight(.semibold))
        }
        // カード面に埋もれないよう地と文字を反転させる（bg2 だと白いカードの上でほぼ消える）。
        .foregroundStyle(Theme.bg1)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.textPrimary.opacity(0.88), in: Capsule())
        .allowsHitTesting(false)
        .transition(.opacity)
        .task {
            // 気づかれないまま出し続けない。タップされたら AppStorage 側で消える。
            try? await Task.sleep(for: .seconds(6))
            withAnimation(.snappy) { tapHintVisible = false }
        }
    }

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

    /// カードの見出し。今週の積み上げを数字でも出して、図が「何のメーターか」を明示する。
    private var weekHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text("今週の積み上げ")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            Text("\(WeeklyMuscleLoad.totalSets(weeklyStatuses))")
                .font(.numS).foregroundStyle(weeklyTotal > 0 ? Theme.lime : Theme.textTertiary)
            Text("セット").font(.caption).foregroundStyle(Theme.textTertiary)
        }
    }

    private var weeklyTotal: Int { WeeklyMuscleLoad.totalSets(weeklyStatuses) }

    /// 図の下の一言。塗り＝今週の量なので「今週まだ空いている部位」を最優先で埋めに行かせる。
    /// そのうえで疲労を見て、いま実際に狙える部位を名指しする。
    private var hintText: String {
        guard weeklyTotal > 0 else {
            return "記録をつけると、鍛えた部位が今週の量ぶんだけ色づきます。部位をタップすると種目ごとの記録が見られます。"
        }
        let untouched = WeeklyMuscleLoad.untouched(weeklyStatuses)
        let ready = MuscleFatigue.recommendedNext(from: statuses)
        // 今週まだ手つかず、かつ回復済み＝いちばん埋めやすい部位。
        if let target = ready.first(where: { untouched.contains($0) }) {
            // 名指しする部位を必ず一覧の先頭に置く（一覧に無い部位を「次は」と言うと読み手が混乱する）。
            let ordered = [target] + untouched.filter { $0 != target }
            return "今週まだ：\(ordered.prefix(3).map(\.label).joined(separator: "・"))。次は\(target.label)が狙い目です。"
        }
        if !untouched.isEmpty {
            return "今週まだ：\(untouched.prefix(3).map(\.label).joined(separator: "・"))。ただ今は疲労が残っているので、回復を待つのも手です。"
        }
        guard let first = ready.first else {
            return "今週は全部位に触れています。しっかり休むのも選択肢です。"
        }
        return "今週は全部位に触れています。積み増すなら\(first.label)が狙い目です。"
    }

    /// 図の脚に被らないタイル幅。脚のシルエットは図の枠幅の 3 割ほどなので左右に 120pt 前後ずつ空くが、
    /// いちばん余白が狭い SE（片側 122pt）でも足首との間が詰まって見えない値で止める。
    private static let metricTileWidth: CGFloat = 106

    /// 体重・体脂肪率。未記録なら入力画面、記録済みなら推移画面へ（初回のつまずきを作らない）。
    /// カード面（bg1）の上に重ねるので、地は一段持ち上げた bg2 にしないと沈んで見えなくなる。
    private func metricTile(label: String, value: String?, systemImage: String) -> some View {
        Button {
            if value == nil { showAddMetric = true } else { showBodyMetrics = true }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(label, systemImage: systemImage)
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Text(value ?? "記録する")
                    .font(value == nil ? .footnote.weight(.semibold) : .numS)
                    .foregroundStyle(value == nil ? Theme.lime : Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(width: Self.metricTileWidth, alignment: .leading)
            .background(Theme.bg2, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            // カード面との明度差が小さいので、縁で「押せる面」であることを示す（反転ボタンと同じ手）。
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Theme.textTertiary.opacity(0.25), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

/// `sheet(item:)` に渡すため（`MuscleGroup` 自体は Identifiable ではない）。
extension MuscleGroup: @retroactive Identifiable {
    public var id: String { rawValue }
}
