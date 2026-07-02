import SwiftUI
import SwiftData

/// マイページ（§5 Profile）。自分のデータ（写真・身体・分析）と設定への集約導線。
/// ソーシャル（フォロー/フィード）は P6 で Social タブ側に実装する。
struct ProfileView: View {
    let userId: UUID

    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var context
    @AppStorage("gymnee.avatarFilename") private var avatarFilename = ""
    @AppStorage("gymnee.avatarURL") private var avatarURLString = ""
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal = 3
    @State private var showProfileEdit = false
    @State private var showWrapped = false
    @Query private var visits: [Visit]

    init(userId: UUID) {
        self.userId = userId
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId })
    }

    /// 完了ワークアウト数。件数表示のためだけに全モデルを実体化しないよう fetchCount で数える。
    private var workoutCount: Int {
        let uid = userId
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.userId == uid && $0.completedAt != nil })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// 週次ストリーク（筋トレは休息が正義のため日次でなく「週N回×連続週」を主指標に）。
    private var weeklyStreak: StreakCalculator.WeeklyStreak {
        StreakCalculator.currentWeeklyStreak(visitDays: visits.map(\.visitedAt), weeklyGoal: weeklyGoal)
    }

    /// 週次ストリークの補足（今週の進捗・フリーズ使用）。日次と違い「休んだ罪悪感」を出さない文面に。
    @ViewBuilder private var weeklyStreakCaption: some View {
        let s = weeklyStreak
        HStack(spacing: Theme.Spacing.sm) {
            Label("週\(weeklyGoal)回 · 今週 \(s.visitsThisWeek)/\(weeklyGoal)",
                  systemImage: s.metThisWeek ? "checkmark.seal.fill" : "target")
                .foregroundStyle(s.metThisWeek ? Theme.lime : Theme.textSecondary)
            if s.freezesUsed > 0 {
                Label("フリーズ\(s.freezesUsed)", systemImage: "snowflake")
                    .foregroundStyle(Theme.info)
            }
            Spacer()
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: Theme.Spacing.lg) {
                    HStack(spacing: Theme.Spacing.md) {
                        AvatarView(filename: avatarFilename, urlString: avatarURLString, size: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.session?.displayName ?? "ゲスト").font(.title2.bold())
                                .lineLimit(1).truncationMode(.tail)
                            Text("プロフィールを編集")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showProfileEdit = true }
                    HStack(spacing: Theme.Spacing.md) {
                        StatPill(value: "\(visits.count)", label: "来店数", tint: Theme.lime, systemImage: "mappin.and.ellipse")
                        StatPill(value: "\(workoutCount)", label: "ワークアウト数", tint: Theme.info, systemImage: "dumbbell.fill")
                        StatPill(value: "\(weeklyStreak.weeks)", label: "連続週", tint: Theme.warning, systemImage: "flame.fill")
                    }
                    weeklyStreakCaption
                }
                .padding(.vertical, Theme.Spacing.sm)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section("マイデータ") {
                NavigationLink(value: AppRoute.photos) { Label("進捗写真", systemImage: "photo.stack") }
                NavigationLink(value: AppRoute.body) { Label("身体メトリクス", systemImage: "ruler") }
                // 分析は専用タブに集約したためここからは外す。
                // Wrapped は sheet で提示（クロージャ型 NavigationLink の遷移先 init 連鎖ハングを回避）。
                Button { showWrapped = true } label: {
                    Label("\(Calendar.current.component(.year, from: .now)) のまとめ", systemImage: "sparkles")
                        .foregroundStyle(Theme.lime)
                }
            }

            Section {
                NavigationLink(value: AppRoute.settings) { Label("設定", systemImage: "gearshape") }
            }
        }
        .navigationTitle("マイページ")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showProfileEdit) { ProfileEditView() }
        .sheet(isPresented: $showWrapped) { GymneeWrappedView(userId: userId, onClose: { showWrapped = false }) }
        // 遷移先は値ベース（AppRoute）。destination は NavigationStack ルート側
        // （CalendarHomeView の gymneeNavigationDestinations）で一括宣言しており、
        // ここ（push されたビュー）では宣言しない。クロージャ型リンクで遷移先を先行生成すると
        // 各遷移先の init が #Predicate 付き @Query を作り直し更新サイクル→ハング（iOS 26 系）に
        // なるため、必ず値ベース＋ルート宣言にする。
    }
}
