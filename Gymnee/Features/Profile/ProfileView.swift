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

    var body: some View {
        List {
            Section {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.energy)
                    VStack(alignment: .leading) {
                        Text(auth.session?.displayName ?? "ゲスト").font(.title3.bold())
                        Text("\(visits.count) 来店・\(StreakCalculator.currentStreak(visitDays: visits.map(\.visitedAt)))日連続")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("マイデータ") {
                NavigationLink { ProgressPhotosView(userId: userId) } label: {
                    Label("進捗写真", systemImage: "photo.stack")
                }
                NavigationLink { BodyMetricsView(userId: userId) } label: {
                    Label("身体メトリクス", systemImage: "ruler")
                }
                NavigationLink { AnalyticsView(userId: userId) } label: {
                    Label("分析ダッシュボード", systemImage: "chart.bar.xaxis")
                }
            }

            Section {
                NavigationLink { SettingsView() } label: {
                    Label("設定", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("マイページ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
