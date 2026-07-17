import SwiftUI
import SwiftData

/// ワークアウト完了サマリー（達成レイヤー / 監査T1a）。
/// 「やり切った瞬間」を無音で終わらせず、連続日数/週次進捗/総量/時間とPR・メニューを祝い、
/// 投稿・共有・分析・閉じるの次アクションへ分岐させる。
/// **1画面に収める**：ページ全体はスクロールさせず、メニュー一覧だけがカード内部でスクロールする。
/// PR を更新した時だけ紙吹雪＋計測タイプ別トロフィーで特別に祝う（普段は静かに完了）。
struct WorkoutSummaryView: View {
    let workout: Workout
    let streak: Int
    /// 今週のアクティブ日数（来店＋完了ワークアウト。週次ゴールタイル「3/5」の分子）。
    let weeklyCount: Int
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
    /// 週次ゴール（カレンダー/設定と同じキー）。達成判定 weeklyCount >= weeklyGoal に使う。
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal = 3

    private var totalVolume: Int {
        let v = workout.exercises.flatMap(\.sets).reduce(0) { $0 + $1.volume }
        return v.isFinite ? Int(v) : 0   // 非有限混入時も Int(∞) でトラップしない
    }

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
            VStack(spacing: Theme.Spacing.md) {
                header
                statTiles
                if hasPR { prStrip }
                menuCard
                actions
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// ヘッダー（コンパクト）。連続日数はタイルへ移し、アイコン＋名前＋ねぎらいの3要素に絞る。
    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                if hasPR {
                    Circle()
                        .fill(Theme.celebration)
                        .frame(width: 72, height: 72)
                        .shadow(color: Theme.limeGlow, radius: 16, y: 4)
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Theme.onLime)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.lime)
                }
            }
            .scaleEffect(appeared ? 1 : 0.4)
            .animation(.bouncy, value: appeared)

            Text(workout.name).font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).truncationMode(.tail)
            Text(appreciationMessage)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    /// 労いのひとこと。内容（PR/連続日数）で出し分ける（乱数は使わず決定的）。
    private var appreciationMessage: String {
        if hasPR { return "限界をひとつ超えた日。しっかり休んで、また積み上げよう。" }
        if streak >= 3 { return "継続は力。今日もちゃんとやり切ったのが一番えらい。" }
        return "今日もお疲れさま。この1回が確実に積み重なっていく。"
    }

    /// スタットタイル1行（連続 / 今週 / 総量 / 時間）。今週は週次ゴール達成で lime。
    private var statTiles: some View {
        HStack(spacing: Theme.Spacing.sm) {
            tile("連続", "\(streak)日")
            tile("今週", "\(weeklyCount)/\(weeklyGoal)",
                 valueColor: weeklyCount >= weeklyGoal ? Theme.lime : Theme.textPrimary)
            tile("総量", "\(totalVolume.formatted())kg")
            durationTile
        }
    }

    private func tile(_ label: String, _ value: String, valueColor: Color = Theme.textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    /// 時間タイル。まとめて後入力した場合はライブ経過が実態と合わないため、
    /// タップで開始時刻・所要時間を手動修正できるようにする（未計測は「—」）。
    private var durationTile: some View {
        Button { showTimeEdit = true } label: {
            VStack(spacing: 2) {
                Text(durationText ?? "—")
                    .font(.title3.bold().monospacedDigit()).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 2) {
                    Text("時間").font(.caption2).foregroundStyle(.secondary)
                    Image(systemName: "pencil").font(.system(size: 8)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// PR バッジ帯（PR時のみ）。1画面レイアウトを守るためカード枠なしの横スクロールに絞る。
    private var prStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ForEach(Array(prs.enumerated()), id: \.element.id) { idx, pr in
                    PRTrophyBadge(type: pr.type, value: pr.value, exerciseName: pr.exerciseName, index: idx)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var menuItems: [WorkoutExercise] {
        workout.exercises.filter { !$0.sets.isEmpty }.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// 今日のメニュー。残り高さを使い、溢れる分はカード内部だけスクロールする（画面全体は固定）。
    /// PR を出した種目にはトロフィーを添える（バッジ帯と合わせた2層目のコンパクト表示）。
    private var menuCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("今日のメニュー", systemImage: "list.bullet.rectangle.fill")
                .font(.subheadline.bold()).foregroundStyle(Theme.textSecondary)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(menuItems) { we in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(we.exercise?.name ?? "種目")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                if we.sets.contains(where: \.isPR) {
                                    Image(systemName: "trophy.fill").font(.caption2).foregroundStyle(Theme.lime)
                                }
                            }
                            Text(we.sets.sorted { $0.setIndex < $1.setIndex }.map(\.detailText).joined(separator: " / "))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.sm) {
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
                // 副アクションは横並びで1段に収める（1画面レイアウト）。
                HStack(spacing: Theme.Spacing.sm) {
                    Button { showShare = true } label: {
                        Label("共有カード", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    Button { onAnalytics() } label: {
                        Label("分析", systemImage: "chart.bar.xaxis").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
            } else {
                // 投稿ボタンが無い（ゲスト/ローカルのみ）時は従来どおり共有カードを主ボタンにする。
                Button { showShare = true } label: {
                    Label("共有カードを作る", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).prominentLime().controlSize(.large)
                Button { onAnalytics() } label: {
                    Label("分析を見る", systemImage: "chart.bar.xaxis").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// サマリーで祝う 1 件の PR（種目×計測タイプ×値）。
private struct SummaryPR: Identifiable {
    let exerciseName: String
    let type: PRType
    let value: Double
    var id: String { "\(exerciseName)-\(type.rawValue)" }
}
