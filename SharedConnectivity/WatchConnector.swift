import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

extension Notification.Name {
    /// 記録のキャンセル等からカレンダータブへ切替えるための要求。
    static let gymneeShowCalendar = Notification.Name("gymnee.showCalendar")
    /// 計画/予定の「開始」から、記録タブで当該ワークアウトを開く要求（userInfo: workoutId）。
    static let gymneeStartWorkout = Notification.Name("gymnee.startWorkout")
    /// 記録の完了サマリーを閉じたあと、育成タブへ切替える要求。
    /// 「この1回が育成にどう効いたか」は育成タブ側で出す（キャラの前で説明する）。
    static let gymneeShowCharacter = Notification.Name("gymnee.showCharacter")
    /// 応援が届いた（userInfo: name/kind）。記録画面が受けて帯に足す。
    static let gymneeCheerReceived = Notification.Name("gymnee.cheerReceived")
    /// 通知タップ等から目的地（タブ）へ遷移する要求（userInfo: type/feedItemId）。
    static let gymneeOpenDestination = Notification.Name("gymnee.openDestination")
    /// Watch：本体から最新スナップショットを受信した。
    static let gymneeSnapshotUpdated = Notification.Name("gymnee.snapshotUpdated")
}

/// Watch ↔ iPhone のリアルタイム橋渡し（§6.10）。
///
/// App Group(UserDefaults) は **端末間では同期しない** ため、別デバイスである Apple Watch と
/// iPhone の間は WCSession 経由で渡す必要がある（App Group は同一端末内の本体⇄Widget用）。
/// - iPhone → Watch: 表示用スナップショット（最新1件で十分なので `updateApplicationContext`）
///
/// 受信側は `SharedStore` を介して処理するので、既存の取り込み導線をそのまま使える。
/// ※ アプリ拡張(Widget)では WatchConnectivity が使えないため、このファイルは本体/Watch ターゲットにのみ含める。
// WCSessionDelegate のコールバックは WC 専用のバックグラウンドスレッドで届く。共有状態
// (SharedStore/NotificationCenter) へのアクセスは main に直列化して競合を避ける。
final class WatchConnector: NSObject, @unchecked Sendable {
    static let shared = WatchConnector()

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

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[snapshotKey] as? Data,
              let snapshot = try? JSONDecoder().decode(GymneeSnapshot.self, from: data) else { return }
        // 共有状態の書込と通知を main に直列化（WC のBGスレッドからの競合を回避）。
        DispatchQueue.main.async {
            SharedStore.save(snapshot)
            NotificationCenter.default.post(name: .gymneeSnapshotUpdated, object: nil)
        }
    }

}
#endif
