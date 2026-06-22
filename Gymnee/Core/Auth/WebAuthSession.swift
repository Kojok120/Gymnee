import Foundation
import AuthenticationServices
import UIKit

/// `ASWebAuthenticationSession` を async/await で包む薄いラッパ（OAuth のブラウザ往復用）。
/// 外部 SDK を足さず OS 標準フレームワークだけで Google サインインの認可フローを回す。
@MainActor
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var current: ASWebAuthenticationSession?

    /// `url` を認可セッションで開き、`callbackScheme://...` のリダイレクトを受け取って返す。
    /// ユーザーキャンセル・失敗時は throw。
    func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let callback {
                    cont.resume(returning: callback)
                } else {
                    cont.resume(throwing: error ?? URLError(.userCancelledAuthentication))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            current = session
            if !session.start() {
                cont.resume(throwing: URLError(.cannotConnectToHost))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            return window ?? UIWindow()
        }
    }
}
