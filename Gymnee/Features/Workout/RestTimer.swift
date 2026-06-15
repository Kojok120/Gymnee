import Foundation
import Observation
import UserNotifications
import ActivityKit

/// レストタイマー（§6.5）。セット完了で起動し、カウントダウン表示＋完了通知。
/// Live Activity 連動は P5 で追加する。
@MainActor
@Observable
final class RestTimer {
    private(set) var remaining: Int = 0
    private(set) var total: Int = 0
    private(set) var isRunning = false
    var presetDuration: Int = 90

    private var task: Task<Void, Never>?
    private let notificationId = "gymnee.restTimer"

    var exerciseName: String = "レスト"
    private var activity: Activity<RestTimerActivityAttributes>?

    func start(seconds: Int? = nil) {
        let duration = seconds ?? presetDuration
        total = duration
        remaining = duration
        isRunning = true
        scheduleNotification(after: duration)
        startLiveActivity(duration: duration)
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.isRunning, self.remaining > 0 else { break }
                self.tick()
            }
        }
    }

    func addTime(_ seconds: Int) {
        guard isRunning else { return }
        remaining += seconds
        total += seconds
        scheduleNotification(after: remaining)
    }

    func stop() {
        isRunning = false
        remaining = 0
        task?.cancel()
        task = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId])
        endLiveActivity()
    }

    // MARK: - Live Activity (§6.10)

    private func startLiveActivity(duration: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endLiveActivity()
        let attributes = RestTimerActivityAttributes(workoutName: "Gymnee")
        let state = RestTimerActivityAttributes.ContentState(
            endDate: Date.now.addingTimeInterval(TimeInterval(duration)),
            exerciseName: exerciseName
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    private func endLiveActivity() {
        guard let activity else { return }
        let current = activity
        self.activity = nil
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }

    private func tick() {
        guard isRunning else { return }
        remaining = max(0, remaining - 1)
        if remaining == 0 { isRunning = false }
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

    private func scheduleNotification(after seconds: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "レスト終了"
        content.body = "次のセットを始めましょう 💪"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [notificationId])
        center.add(request)
    }
}
