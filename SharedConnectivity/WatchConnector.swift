import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

extension Notification.Name {
    /// iOS 本体：Watch からクイックチェックイン要求を受信した。
    static let gymneeWatchCheckInReceived = Notification.Name("gymnee.watchCheckInReceived")
    /// チェックイン完了。記録タブへ誘導するために RootView が購読する。
    static let gymneeDidCheckIn = Notification.Name("gymnee.didCheckIn")
    /// 完了サマリー等から分析タブへ切替えるための要求。
    static let gymneeShowAnalytics = Notification.Name("gymnee.showAnalytics")
    /// 通知タップ等から目的地（タブ）へ遷移する要求（userInfo: type/feedItemId）。
    static let gymneeOpenDestination = Notification.Name("gymnee.openDestination")
    /// Watch：本体から最新スナップショットを受信した。
    static let gymneeSnapshotUpdated = Notification.Name("gymnee.snapshotUpdated")
}

/// Watch ↔ iPhone のリアルタイム橋渡し（§6.10）。
///
/// App Group(UserDefaults) は **端末間では同期しない** ため、別デバイスである Apple Watch と
/// iPhone の間は WCSession 経由で渡す必要がある（App Group は同一端末内の本体⇄Widget用）。
/// - Watch → iPhone: クイックチェックイン要求（到達保証つき `transferUserInfo`／即時は `sendMessage`）
/// - iPhone → Watch: 表示用スナップショット（最新1件で十分なので `updateApplicationContext`）
///
/// 受信側はいずれも従来どおり `SharedStore` を介して処理するので、既存の取り込み導線をそのまま使える。
/// ※ アプリ拡張(Widget)では WatchConnectivity が使えないため、このファイルは本体/Watch ターゲットにのみ含める。
// WCSessionDelegate のコールバックは WC 専用のバックグラウンドスレッドで届く。共有状態
// (SharedStore/NotificationCenter) へのアクセスは main に直列化して競合を避ける。
final class WatchConnector: NSObject, @unchecked Sendable {
    static let shared = WatchConnector()

    private let checkInKey = "checkInAt"
    private let snapshotKey = "snapshot"

    private override init() { super.init() }

    /// アプリ起動時に 1 回呼ぶ。WCSession を有効化しデリゲートを接続する。
    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    // MARK: - Watch → iPhone

    /// Watch から本体へクイックチェックインを送る。reachable なら即時、そうでなければキュー転送。
    func sendCheckIn(at date: Date = Date()) {
        let payload: [String: Any] = [checkInKey: date.timeIntervalSince1970]
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            SharedStore.addPendingCheckIn(at: date)
            return
        }
        let session = WCSession.default
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                // 即時送信に失敗したら到達保証つきのキュー転送へフォールバック。
                WCSession.default.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
        #else
        SharedStore.addPendingCheckIn(at: date)
        #endif
    }

    // MARK: - iPhone → Watch

    /// 本体スナップショットを Watch へ配布する（手首側のストリーク/今週表示の更新）。
    func sendSnapshot(_ snapshot: GymneeSnapshot) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        // Watch 未ペアリング/未インストール時の DeviceNotPaired エラーログを避ける。
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? session.updateApplicationContext([snapshotKey: data])
        #endif
    }
}

#if canImport(WatchConnectivity)
extension WatchConnector: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingCheckIn(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleIncomingCheckIn(userInfo)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[snapshotKey] as? Data,
              let snapshot = try? JSONDecoder().decode(GymneeSnapshot.self, from: data) else { return }
        // 共有状態の書込と通知を main に直列化（WC のBGスレッドからの競合を回避）。
        DispatchQueue.main.async {
            SharedStore.save(snapshot)
            NotificationCenter.default.post(name: .gymneeSnapshotUpdated, object: nil)
        }
    }

    private func handleIncomingCheckIn(_ payload: [String: Any]) {
        guard let ts = payload[checkInKey] as? Double else { return }
        let date = Date(timeIntervalSince1970: ts)
        // App Group キュー書込と通知を main に直列化（既存の取り込み導線が拾う）。
        DispatchQueue.main.async {
            SharedStore.addPendingCheckIn(at: date)
            NotificationCenter.default.post(name: .gymneeWatchCheckInReceived, object: nil)
        }
    }
}
#endif
