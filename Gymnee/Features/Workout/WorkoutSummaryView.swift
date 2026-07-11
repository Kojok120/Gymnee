import SwiftUI
import SwiftData

/// ワークアウト完了サマリー（達成レイヤー / 監査T1a）。
/// 「やり切った瞬間」を無音で終わらせず、総ボリューム/セット/時間/PRを祝い、
/// 共有・分析・閉じるの次アクションへ分岐させる。
/// PR を更新した時だけ紙吹雪＋計測タイプ別トロフィーで特別に祝う（普段は静かに完了）。
struct WorkoutSummaryView: View {
    let workout: Workout
    let streak: Int
    /// 投稿ボタンの公開範囲表示（例: "フレンド"）。onPost が nil なら未使用。
    var postVisibilityLabel: String = ""
    /// 「ソーシャルに投稿」の明示同意アクション（fail-closed）。nil＝非表示（ゲスト/ローカルのみ）。
    var onPost: (() -> Void)? = nil
    var onAnalytics: () -> Void
    var onClose: () -> Void

    @State private var appeared = false
    @State private var showShare = false
    @State private var showTimeEdit = false
    @State private var posted = false

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
        WorkoutDuration.minutes(
            date: workout.date, completedAt: workout.completedAt, durationSeconds: workout.durationSeconds
        ).map { "\($0)分" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    header
                    if hasPR { prTrophies }
                    statGrid
                    todayMenu
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
            .sheet(isPresented: $showTimeEdit) {
                WorkoutTimeEditSheet(workout: workout)
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
            Text(appreciationMessage)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
    }

    /// 労いのひとこと。内容（PR/連続日数）で出し分ける（乱数は使わず決定的）。
    private var appreciationMessage: String {
        if hasPR { return "限界をひとつ超えた日。しっかり休んで、また積み上げよう。" }
        if streak >= 3 { return "継続は力。今日もちゃんとやり切ったのが一番えらい。" }
        return "今日もお疲れさま。この1回が確実に積み重なっていく。"
    }

    /// 今日のメニュー一覧（種目ごとのセット内訳）。フィードカードと同じ表記で並べる。
    @ViewBuilder private var todayMenu: some View {
        let items = workout.exercises
            .filter { !$0.sets.isEmpty }
            .sorted { $0.orderIndex < $1.orderIndex }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("今日のメニュー", systemImage: "list.bullet.rectangle.fill")
                    .font(.subheadline.bold()).foregroundStyle(Theme.textSecondary)
                ForEach(items) { we in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(we.exercise?.name ?? "種目")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text(we.sets.sorted { $0.setIndex < $1.setIndex }.map(\.detailText).joined(separator: " / "))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
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
            durationStat
        }
    }

    /// 所要時間セル。まとめて後入力した場合はライブ経過が実態と合わないため、
    /// タップで開始時刻・所要時間を手動修正できるようにする（未計測は「—」）。
    private var durationStat: some View {
        Button { showTimeEdit = true } label: {
            VStack(spacing: 4) {
                Text(durationText ?? "—")
                    .font(.title2.bold().monospacedDigit()).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 4) {
                    Text("所要時間").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "pencil").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.md)
            .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
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
            // 投稿は明示同意（fail-closed）。押さなければ非公開のまま（後から投稿メニューで公開可）。
            if let onPost {
                Button {
                    onPost()
                    withAnimation(.smooth) { posted = true }
                } label: {
                    Label(posted ? "投稿しました" : "ソーシャルに投稿",
                          systemImage: posted ? "checkmark.circle.fill" : "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).prominentLime().controlSize(.large)
                .disabled(posted)
                .sensoryFeedback(.success, trigger: posted)
                Text(posted ? "フィードに公開されました。" : "公開範囲: \(postVisibilityLabel)。押さなければ非公開のままです。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            // 投稿ボタンが無い（ゲスト/ローカルのみ）時は従来どおり共有カードを主ボタンにする。
            if onPost == nil {
                Button { showShare = true } label: {
                    Label("共有カードを作る", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).prominentLime().controlSize(.large)
            } else {
                Button { showShare = true } label: {
                    Label("共有カードを作る", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
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
