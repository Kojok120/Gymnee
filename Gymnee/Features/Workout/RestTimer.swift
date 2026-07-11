import Foundation
import Observation
import UserNotifications
import ActivityKit

/// レストタイマー（§6.5）。セット完了で起動し、カウントダウン表示＋完了通知＋Live Activity。
/// 残りは「終了時刻(endDate)」からの実時計差分で毎回算出する。毎秒カウンターを減算する方式だと、
/// アプリがバックグラウンド（画面オフ）で中断された間だけ進まず、通知/Live Activity とズレるため。
@MainActor
@Observable
final class RestTimer {
    private(set) var remaining: Int = 0
    private(set) var total: Int = 0
    private(set) var isRunning = false
    /// 既定レスト秒数。設定 `gymnee.restSeconds` が真実（未設定は90）。
    var presetDuration: Int {
        let v = UserDefaults.standard.integer(forKey: "gymnee.restSeconds")
        return v > 0 ? v : 90
    }

    /// レスト終了の実時刻。残りはここからの差分で算出する（真実は endDate）。
    private var endDate: Date?
    private var task: Task<Void, Never>?
    private let notificationId = "gymnee.restTimer"

    var exerciseName: String = "レスト"
    private var activity: Activity<RestTimerActivityAttributes>?

    func start(seconds: Int? = nil) {
        let duration = seconds ?? presetDuration
        total = duration
        endDate = Date.now.addingTimeInterval(TimeInterval(duration))
        remaining = duration
        isRunning = true
        scheduleNotification()
        startLiveActivity()
        startTicking()
    }

    func addTime(_ seconds: Int) {
        guard isRunning, let end = endDate else { return }
        endDate = end.addingTimeInterval(TimeInterval(seconds))
        total += seconds
        refresh()
        scheduleNotification()
        updateLiveActivity()
    }

    func stop() {
        isRunning = false
        remaining = 0
        endDate = nil
        task?.cancel()
        task = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId])
        endLiveActivity()
    }

    /// 実時計から残りを再計算して反映する（毎秒の tick／フォアグラウンド復帰時に即時同期）。
    func refresh() {
        guard isRunning else { return }
        remaining = secondsUntilEnd()
        if remaining == 0 {
            isRunning = false
            task?.cancel()
            task = nil
            // フォアグラウンドで終了を迎えたらチャイムを鳴らす（サイレントスイッチでも鳴る）。
            // バックグラウンド中の終了は通知音が担い、復帰時の refresh はここを通るが
            // endDate をとうに過ぎた「復帰同期」で今さら鳴らさない（終了直後 2 秒以内のみ）。
            if let end = endDate, Date.now.timeIntervalSince(end) < 2 {
                RestChime.playIfEnabled()
            }
        }
    }

    private func secondsUntilEnd() -> Int {
        guard let endDate else { return 0 }
        return max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
    }

    /// 毎秒 endDate から残りを再計算する（減算ではないのでバックグラウンド中断後も復帰時に正しい値へ戻る）。
    private func startTicking() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.isRunning else { break }
                self.refresh()
            }
        }
    }

    // MARK: - Live Activity (§6.10)

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let endDate else { return }
        endLiveActivity()
        let attributes = RestTimerActivityAttributes(workoutName: "Gymnee")
        let state = RestTimerActivityAttributes.ContentState(endDate: endDate, exerciseName: exerciseName)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    /// +30 等で終了時刻を延長したら Live Activity の endDate も更新する（ロック画面と一致させる）。
    private func updateLiveActivity() {
        guard let activity, let endDate else { return }
        let state = RestTimerActivityAttributes.ContentState(endDate: endDate, exerciseName: exerciseName)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    private func endLiveActivity() {
        guard let activity else { return }
        let current = activity
        self.activity = nil
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(total - remaining) / Double(total)
    }

    var displayText: String {
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }

    private func scheduleNotification() {
        // 許諾は NotificationService が一元管理する（毎回ここで要求すると重複・競合する）。
        // 発火時刻は endDate 基準にし、アプリの残り表示とズレないようにする。
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "レスト終了"
        content.body = "次のセットを始めましょう 💪"
        content.sound = .default
        let secs = max(1, Int((endDate ?? Date.now).timeIntervalSinceNow.rounded(.up)))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(secs), repeats: false)
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [notificationId])
        center.add(request)
    }
}
