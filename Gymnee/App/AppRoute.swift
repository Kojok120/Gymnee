import SwiftUI

/// アプリ内ナビゲーションの値ルート（§5）。
///
/// navigationDestination は **NavigationStack のルート側で一括宣言**する。
/// iOS 26.5 では、push されたビュー（例: ProfileView）の上に置いた
/// `navigationDestination(for:)` が、その内部の NavigationLink から解決されず
/// 「no matching navigationDestination … The link cannot be activated」となり
/// 遷移できない（26.4 までは動いていた）。ルートで宣言すれば、スタック内の
/// どのリンクからも確実に解決でき、全 iOS で安定する。
enum AppRoute: Hashable {
    case profile
    case photos
    case body
    case analytics
    /// カレンダーホーム。タブから外し「その他」配下へ移したため値ルートで開く。
    case calendar
    case shop
    case settings
    /// ブロック中のユーザー一覧（設定から）。遷移先 init が @Query を作るため必ず値ベースで開く。
    case blockedUsers(UUID)
    case workoutDetail(Workout)
    case exerciseDetail(Exercise)
}

extension View {
    /// CalendarHome の NavigationStack ルートに付与する共通 destination 宣言。
    /// すべての AppRoute をここで解決する（push 先での個別宣言は行わない）。
    func gymneeNavigationDestinations(userId: UUID) -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .profile: ProfileView(userId: userId)
            case .photos: ProgressPhotosView(userId: userId)
            case .body: BodyMetricsView(userId: userId)
            case .analytics: AnalyticsView(userId: userId)
            case .calendar:
                CalendarHomeContent(userId: userId)
                    .navigationTitle("カレンダー")
            case .shop:
                ShopContent(userId: userId)
                    .navigationTitle("ショップ").navigationBarTitleDisplayMode(.inline)
            case .settings: SettingsView()
            case .blockedUsers(let uid): BlockedUsersView(currentUserId: uid)
            case .workoutDetail(let workout): WorkoutDetailView(workout: workout)
            case .exerciseDetail(let exercise): ExerciseDetailView(exercise: exercise, userId: userId)
            }
        }
    }
}
