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
    case gyms
    case profile
    case photos
    case body
    case analytics
    case settings
}

/// ワークアウト詳細への遷移値。WorkoutHome の activeWorkout(navigationDestination(item:))
/// と Workout 型が衝突しないよう、生の Workout ではなくラッパで push する。
/// Hashable は id ベースで安定させる。
struct WorkoutRef: Hashable {
    let workout: Workout
    static func == (lhs: WorkoutRef, rhs: WorkoutRef) -> Bool { lhs.workout.id == rhs.workout.id }
    func hash(into hasher: inout Hasher) { hasher.combine(workout.id) }
}

extension View {
    /// CalendarHome の NavigationStack ルートに付与する共通 destination 宣言。
    /// すべての AppRoute をここで解決する（push 先での個別宣言は行わない）。
    func gymneeNavigationDestinations(userId: UUID) -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .gyms: GymListView(userId: userId)
            case .profile: ProfileView(userId: userId)
            case .photos: ProgressPhotosView(userId: userId)
            case .body: BodyMetricsView(userId: userId)
            case .analytics: AnalyticsView(userId: userId)
            case .settings: SettingsView()
            }
        }
    }
}
