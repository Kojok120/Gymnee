import SwiftUI
import SwiftData

/// マイページ（§5 Profile）。自分のデータ（写真・身体・分析）と設定への集約導線。
/// ソーシャル（フォロー/フィード）は P6 で Social タブ側に実装する。
struct ProfileView: View {
    let userId: UUID

    @Environment(AuthService.self) private var auth
    @Query private var visits: [Visit]

    init(userId: UUID) {
        self.userId = userId
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId })
    }

    private var currentStreak: Int { StreakCalculator.currentStreak(visitDays: visits.map(\.visitedAt)) }
    private var longestStreak: Int { StreakCalculator.longestStreak(visitDays: visits.map(\.visitedAt)) }

    var body: some View {
        List {
            Section {
                VStack(spacing: Theme.Spacing.lg) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(Theme.lime)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.session?.displayName ?? "ゲスト").font(.title2.bold())
                            Text("トレーニングを続けています")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    HStack(spacing: Theme.Spacing.md) {
                        StatPill(value: "\(visits.count)", label: "来店", tint: Theme.lime, systemImage: "mappin.and.ellipse")
                        StatPill(value: "\(currentStreak)", label: "連続日", tint: Theme.warning, systemImage: "flame.fill")
                        StatPill(value: "\(longestStreak)", label: "最長", tint: Theme.textPrimary, systemImage: "trophy.fill")
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section("マイデータ") {
                NavigationLink(value: Route.photos) { Label("進捗写真", systemImage: "photo.stack") }
                NavigationLink(value: Route.body) { Label("身体メトリクス", systemImage: "ruler") }
                NavigationLink(value: Route.analytics) { Label("分析ダッシュボード", systemImage: "chart.bar.xaxis") }
            }

            Section {
                NavigationLink(value: Route.settings) { Label("設定", systemImage: "gearshape") }
            }
        }
        .navigationTitle("マイページ")
        .navigationBarTitleDisplayMode(.inline)
        // 値ベースの遅延ナビゲーション。遷移先は「タップ時のみ」生成する。
        // クロージャ型 NavigationLink { DestView(...) } は List 描画のたびに遷移先を先行生成し、
        // 各遷移先の init が #Predicate 付き @Query を毎回作り直すため、NavigationStack の
        // 差分計算が更新サイクルに陥り iOS 26 系でメインスレッドがハングしていた（ウォッチドッグ kill）。
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .photos: ProgressPhotosView(userId: userId)
            case .body: BodyMetricsView(userId: userId)
            case .analytics: AnalyticsView(userId: userId)
            case .settings: SettingsView()
            }
        }
    }

    private enum Route: Hashable { case photos, body, analytics, settings }
}
