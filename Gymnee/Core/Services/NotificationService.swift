import Foundation
import UserNotifications
import UIKit
import Observation

/// 通知の集約（§6.10 / §6.12 深掘り）。許諾要求・フォアグラウンド表示・各種リマインドを一元管理。
@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    /// 通知の種類別 ON/OFF の保存キー（設定画面の @AppStorage と共有）。
    /// プッシュ系（likes / friendCheckin）はサーバー側 profiles 列でも制御する。
    enum PrefKey {
        static let likes = "gymnee.notif.likes"
        static let friendCheckin = "gymnee.notif.friendCheckin"
        /// 旧ストリーク通知と同じ保存キーを引き継ぐ。オフにした利用者へ再通知しないため。
        static let reengagement = "gymnee.notif.streak"
        static let planned = "gymnee.notif.planned"
        static let weeklyRecap = "gymnee.notif.weeklyRecap"
        /// AI コーチの声かけ（朝の予告・完了後の称賛）。
        static let coach = "gymnee.notif.coach"
    }

    /// 未設定（キー無し）は ON 扱い。
    private func prefEnabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
    }

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

    /// 在庫リマインド（補給ロギングから枯渇予測）。商品ごとに 1 件（重複排除）。
    func notifySupplyLow(productId: UUID, productName: String) {
        fire(id: "gymnee.supply.\(productId.uuidString)", title: "そろそろ無くなりそう", body: "\(productName) の在庫が少なくなっています。補充しますか？", userInfo: ["type": "shop"])
    }

    /// 週次リキャップ（毎週日曜 19:00）。今週の成果を振り返らせ、再訪を促す。
    func scheduleWeeklyRecap() {
        let id = "gymnee.weeklyRecap"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard prefEnabled(PrefKey.weeklyRecap) else { return }
        var comps = DateComponents()
        comps.weekday = 1 // 日曜
        comps.hour = 19; comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        schedule(id: id, title: "今週のまとめ📊", body: "今週のトレーニングを振り返ってみよう。", trigger: trigger, userInfo: ["type": "recap"])
    }

    /// 最終記録から3日空いたときの再開リマインド。連続記録を失う不安ではなく、
    /// 無理なく戻れる入口を渡す。複数日ぶんを予約し、完了時は接頭辞で一括解除する。
    func scheduleReengagementReminders(lastCompletedAt: Date?, calendar: Calendar = .current) {
        Task { @MainActor in
            await removePendingNotifications(prefix: "gymnee.reengagement.")
            center.removePendingNotificationRequests(withIdentifiers: ["gymnee.streakRisk"])
            guard prefEnabled(PrefKey.reengagement) else { return }
            for date in ReengagementReminder.scheduledDates(
                lastCompletedAt: lastCompletedAt,
                now: .now,
                calendar: calendar
            ) {
                let id = "gymnee.reengagement.\(ReengagementReminder.identifierDate(date, calendar: calendar))"
                var comps = calendar.dateComponents([.year, .month, .day], from: date)
                comps.hour = ReengagementReminder.hour
                comps.minute = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                schedule(
                    id: id,
                    title: "また一歩だけ動いてみよう",
                    body: "短いトレーニングから、無理のないペースで再開できます。",
                    trigger: trigger,
                    userInfo: ["type": "workout"]
                )
            }
        }
    }

    /// 予定ワークアウトのリマインド（当日朝 8:00）。
    func schedulePlannedWorkouts(_ items: [(id: UUID, name: String, date: Date)]) {
        guard prefEnabled(PrefKey.planned) else {
            for item in items {
                center.removePendingNotificationRequests(withIdentifiers: ["gymnee.planned.\(item.id.uuidString)"])
            }
            return
        }
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

    // MARK: - AI コーチの声かけ（#79）

    /// コーチの声かけは **1 日 2 回まで**（朝の予告 + 完了後の称賛）。
    /// 「関係」を作るのが目的なので、鳴らしすぎると逆に切られる。
    enum CoachNotice {
        static let morningPrefix = "gymnee.coach.morning."
        static let morningHour = 7
    }

    /// 朝の予告。今日のメニューがあればその名前を、無ければ今週の残りを伝える。
    /// **サボりを責めない**（週次ストリークの思想に合わせる）。
    func scheduleCoachMorning(planTitle: String?, weeklyRemaining: Int, calendar: Calendar = .current) {
        Task { @MainActor in
            await removePendingNotifications(prefix: CoachNotice.morningPrefix)
            guard prefEnabled(PrefKey.coach) else { return }

            let body: String
            if let planTitle {
                body = "今日は「\(planTitle)」。いつもの時間にどう？"
            } else if weeklyRemaining > 0 {
                body = "今週はあと\(weeklyRemaining)回。無理のない日に入れよう"
            } else {
                body = "今週の目標はもう達成してる。今日は休んでもいい"
            }

            let today = calendar.startOfDay(for: .now)
            var firstDay = today
            var firstComponents = calendar.dateComponents([.year, .month, .day], from: firstDay)
            firstComponents.hour = CoachNotice.morningHour
            firstComponents.minute = 0
            if let firstFireDate = calendar.date(from: firstComponents), firstFireDate <= .now {
                firstDay = calendar.date(byAdding: .day, value: 1, to: firstDay) ?? firstDay
            }
            for offset in 0..<ReengagementReminder.horizonDays {
                guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
                var comps = calendar.dateComponents([.year, .month, .day], from: date)
                comps.hour = CoachNotice.morningHour
                comps.minute = 0
                let id = CoachNotice.morningPrefix + ReengagementReminder.identifierDate(date, calendar: calendar)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                schedule(id: id, title: "コーチから", body: body, trigger: trigger, userInfo: ["type": "coach"])
            }
        }
    }

    /// 記録を終えた直後の称賛。予約ではなく即時に出す。
    func notifyCoachPraise(workoutName: String, streakWeeks: Int) {
        guard prefEnabled(PrefKey.coach) else { return }
        let body = streakWeeks >= 2
            ? "「\(workoutName)」おつかれ。\(streakWeeks)週続いてる"
            : "「\(workoutName)」おつかれ。よく来たね"
        fire(id: "gymnee.coach.praise", title: "コーチから", body: body, userInfo: ["type": "coach"])
    }

    func cancelCoachNotices() {
        Task { @MainActor in await removePendingNotifications(prefix: CoachNotice.morningPrefix) }
    }

    // MARK: - 種類別トグルOFF時の即時キャンセル（設定画面から呼ぶ）

    func cancelReengagementReminders() {
        Task { @MainActor in
            await removePendingNotifications(prefix: "gymnee.reengagement.")
            // v9より前に予約済みのストリーク通知も、この移行中に確実に消す。
            center.removePendingNotificationRequests(withIdentifiers: ["gymnee.streakRisk"])
        }
    }
    func cancelWeeklyRecap() {
        center.removePendingNotificationRequests(withIdentifiers: ["gymnee.weeklyRecap"])
    }
    /// 予定ワークアウトは id が動的（gymnee.planned.<uuid>）なので接頭辞で一括除去。
    func cancelPlannedReminders() {
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter { $0.hasPrefix("gymnee.planned.") }
            guard !ids.isEmpty else { return }
            Task { @MainActor in self.center.removePendingNotificationRequests(withIdentifiers: ids) }
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

    private func removePendingNotifications(prefix: String) async {
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // レストタイマーはフォアグラウンドではアプリ内チャイム（RestChime・サイレントでも鳴る）が
        // 担当するため通知音を出さない（二重に鳴るのを防ぐ）。バナーは残す。
        // 応援は記録中に届く。バナーで手を止めさせず、記録画面の帯に足すだけにする。
        let info = notification.request.content.userInfo
        if info["type"] as? String == "cheer" {
            postCheer(info)
            completionHandler([])
            return
        }
        if notification.request.identifier == RestTimer.notificationId {
            completionHandler([.banner, .list])
        } else {
            completionHandler([.banner, .sound, .list])
        }
    }

    /// 通知タップ時のルーティング（ローカル/リモート共通）。userInfo の type を見て該当タブへ。
    /// 届いた応援を記録画面へ流す。プッシュの中身をそのまま使い、取り直しを待たせない。
    nonisolated private func postCheer(_ info: [AnyHashable: Any]) {
        let name = (info["cheererName"] as? String) ?? "フレンド"
        let kind = (info["cheerKind"] as? String) ?? "fire"
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .gymneeCheerReceived, object: nil,
                userInfo: ["name": name, "kind": kind]
            )
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let type = info["type"] as? String
        let feedItemId = info["feedItemId"] as? String
        if type == "cheer" { postCheer(info) }
        Task { @MainActor in
            var ui: [String: String] = [:]
            if let type { ui["type"] = type }
            if let feedItemId { ui["feedItemId"] = feedItemId }
            NotificationCenter.default.post(name: .gymneeOpenDestination, object: nil, userInfo: ui)
        }
        completionHandler()
    }
}
