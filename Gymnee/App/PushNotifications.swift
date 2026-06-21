import SwiftUI
import UIKit

/// APNs デバイストークンの集約点。`AppDelegate` が書き込み、`AppEnvironment` が Supabase へ転送する。
/// 実際の APNs 配信には `aps-environment` entitlement と APNs 鍵（サーバ側）が必要。
@MainActor
@Observable
final class PushTokenCenter {
    static let shared = PushTokenCenter()

    private(set) var apnsToken: String?
    private(set) var lastError: String?

    /// トークン取得時のフック（AppEnvironment が Supabase 登録処理を差し込む）。
    @ObservationIgnored var onToken: ((String) -> Void)?

    private init() {}

    func update(_ token: String) {
        apnsToken = token
        lastError = nil
        onToken?(token)
    }

    func fail(_ error: Error) {
        lastError = error.localizedDescription
    }
}

/// SwiftUI App ライフサイクルに APNs コールバックを橋渡しする AppDelegate。
/// `GymneeApp` に `@UIApplicationDelegateAdaptor` で接続する。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in PushTokenCenter.shared.update(token) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in PushTokenCenter.shared.fail(error) }
    }
}
