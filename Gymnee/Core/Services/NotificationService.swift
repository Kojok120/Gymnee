import Foundation
import UserNotifications
import UIKit
import Observation

/// 通知の集約（§6.10 / §6.12 深掘り）。許諾要求・フォアグラウンド表示・各種リマインドを一元管理。
@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private(set) var isAuthorized = false
    /// 生の許諾状態。プリパーミッション/再有効化の出し分けに使う。
    private(set) var status: UNAuthorizationStatus = .notDetermined

    /// アプリ起動時にデリゲートを設定（フォアグラウンドでもバナー表示）。
    func configure() {
        center.delegate = self
        center.getNotificationSettings { settings in
            Task { @MainActor in
                self.status = settings.authorizationStatus
                self.isAuthorized = settings.authorizationStatus == .authorized
                // 既に許諾済みなら APNs 登録を更新（トークンのローテーション追従）。
                if self.isAuthorized { self.registerForRemotePush() }
            }
        }
    }

    /// 現在の許諾状態を取り直す（設定アプリから戻った時など）。
    func refreshStatus() async {
        let settings = await center.notificationSettings()
        status = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
    }

    func requestAuthorization() async {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        isAuthorized = granted
        status = granted ? .authorized : .denied
        if granted { registerForRemotePush() }
    }

    /// iOS の設定アプリ（本アプリのページ）を開く。拒否後の再有効化導線。
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// APNs リモート通知の登録を要求する（成功/失敗は AppDelegate → PushTokenCenter に届く）。
    /// 実配信には `aps-environment` entitlement と APNs 鍵が必要。
    func registerForRemotePush() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - 通知種別

    /// PR 達成（アプリ内トーストの補完として通知センターにも残す）。
    func notifyPR(_ text: String) {
        fire(id: "gymnee.pr.\(UUID().uuidString)", title: "新記録達成！🏆", body: text, userInfo: ["type": "analytics"])
    }

    /// 在庫リマインド（補給ロギングから枯渇予測）。商品ごとに 1 件（重複排除）。
    func notifySupplyLow(productId: UUID, productName: String) {
        fire(id: "gymnee.supply.\(productId.uuidString)", title: "そろそろ無くなりそう", body: "\(productName) の在庫が少なくなっています。補充しますか？", userInfo: ["type": "shop"])
    }

    /// 週次リキャップ（毎週日曜 19:00）。今週の成果を振り返らせ、再訪を促す。
    func scheduleWeeklyRecap() {
        let id = "gymnee.weeklyRecap"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        var comps = DateComponents()
        comps.weekday = 1 // 日曜
        comps.hour = 19; comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        schedule(id: id, title: "今週のまとめ📊", body: "今週のトレーニングを振り返ってみよう。", trigger: trigger, userInfo: ["type": "recap"])
    }

    /// 連続記録の途切れ予告。今日の 20:00 に「まだチェックインしていない」場合の催促を予約。
    func scheduleStreakReminder(streak: Int, hasCheckedInToday: Bool) {
        let id = "gymnee.streakRisk"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard streak > 0, !hasCheckedInToday else { return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.hour = 20; comps.minute = 0
        guard let fireDate = Calendar.current.date(from: comps), fireDate > .now else { return }
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        schedule(id: id, title: "連続\(streak)日が途切れそう🔥", body: "今日もチェックインして記録を伸ばそう！", trigger: trigger, userInfo: ["type": "checkin"])
    }

    /// 予定ワークアウトのリマインド（当日朝 8:00）。
    func schedulePlannedWorkouts(_ items: [(id: UUID, name: String, date: Date)]) {
        for item in items {
            let id = "gymnee.planned.\(item.id.uuidString)"
            center.removePendingNotificationRequests(withIdentifiers: [id])
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: item.date)
            comps.hour = 8; comps.minute = 0
            guard let fireDate = Calendar.current.date(from: comps), fireDate > .now else { continue }
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            schedule(id: id, title: "今日の予定: \(item.name)", body: "ワークアウトの予定があります💪", trigger: trigger, userInfo: ["type": "workout"])
        }
    }

    // MARK: - helpers

    private func fire(id: String, title: String, body: String, userInfo: [String: String] = [:]) {
        schedule(id: id, title: title, body: body, trigger: nil, userInfo: userInfo)
    }

    private func schedule(id: String, title: String, body: String, trigger: UNNotificationTrigger?, userInfo: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// 通知タップ時のルーティング（ローカル/リモート共通）。userInfo の type を見て該当タブへ。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let type = info["type"] as? String
        let feedItemId = info["feedItemId"] as? String
        Task { @MainActor in
            var ui: [String: String] = [:]
            if let type { ui["type"] = type }
            if let feedItemId { ui["feedItemId"] = feedItemId }
            NotificationCenter.default.post(name: .gymneeOpenDestination, object: nil, userInfo: ui)
        }
        completionHandler()
    }
}
