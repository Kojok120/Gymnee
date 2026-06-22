import Foundation
import SwiftData
import Observation
import AuthenticationServices
import CryptoKit

/// セッション状態の保持と Profile 行の整合を司る（§6.1）。
/// View は `session` を観測し、未ログインなら Onboarding、ログイン済みなら本体を表示する。
///
/// Sign in with Apple は Apple 公式の `SignInWithAppleButton` から
/// `prepareAppleRequest(_:)`（nonce 付与）→ `completeSignInWithApple(_:)` の順で呼ぶ。
/// Supabase 接続時は identityToken を Supabase Auth に渡してリモートセッションを得る。
@MainActor
@Observable
final class AuthService {
    private(set) var session: UserSession?
    private let provider: AuthProviding
    private var context: ModelContext?

    /// Supabase 接続時のみ設定（未設定ならローカル経路）。
    @ObservationIgnored private var supabase: SupabaseClient?
    /// 進行中の Sign in with Apple の生 nonce（sha256 を request に載せ、生値を Supabase に渡す）。
    @ObservationIgnored private var currentNonce: String?

    /// バックエンド(Supabase)で認証済みか（トークン保持中）。
    private(set) var isBackendAuthenticated = false
    /// バックエンドサインイン成功時のフック（旧 userId, 新 userId）。AppEnvironment が移行＋同期を差し込む。
    @ObservationIgnored var onBackendSignIn: ((_ oldUserId: UUID?, _ newUserId: UUID) -> Void)?

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// OAuth(Google) のブラウザ往復用（ASWebAuthenticationSession ラッパ）。
    @ObservationIgnored private let webAuth = WebAuthSession()
    private let accessTokenKey = "gymnee.supabase.accessToken"
    private let refreshTokenKey = "gymnee.supabase.refreshToken"
    private let backendUserIdKey = "gymnee.supabase.userId"
    private let backendNameKey = "gymnee.supabase.displayName"

    var isSignedIn: Bool { session != nil }
    var currentUserId: UUID? { session?.userId }
    /// バックエンド(Supabase)が構成済みで、メール/Google サインインが使えるか。
    var isBackendAvailable: Bool { supabase != nil }
    /// 永続化済みのバックエンドセッションがあるか（再起動後の復元判定／Settings 表示用）。
    var hasPersistedBackendSession: Bool { defaults.string(forKey: refreshTokenKey) != nil }

    init(provider: AuthProviding = MockAuthProvider()) {
        self.provider = provider
    }

    /// ModelContext を注入し、前回セッションがあれば復元する。
    func bootstrap(context: ModelContext) {
        self.context = context
        if let restored = provider.restoreSession() {
            session = restored
            ensureProfile(for: restored)
        }
    }

    /// Supabase クライアントを差し込む（リモート同期と認証を有効化）。
    func configureSupabase(_ client: SupabaseClient?) {
        self.supabase = client
    }

    /// 表示名で他ユーザーを検索する（相互フォローの相手探し）。バックエンド未認証なら空。
    /// 通信失敗は throw で呼び出し側へ伝える（「該当なし」と区別してフィードバックするため）。
    func searchUsers(query: String) async throws -> [SupabaseClient.RemoteProfile] {
        guard let supabase, isBackendAuthenticated else { return [] }
        return try await supabase.searchProfiles(nameQuery: query, excluding: currentUserId)
    }

    func signIn(displayName: String) {
        guard let restored = try? provider.signIn(displayName: displayName) else { return }
        session = restored
        ensureProfile(for: restored)
    }

    func signOut() {
        provider.signOut()
        clearBackendSession()
        let client = supabase
        Task { await client?.setAccessToken(nil) }
        session = nil
    }

    /// 再起動後にバックエンドセッションを復元する（refresh_token でアクセストークンを更新）。
    /// GymneeApp の起動時 task から呼ぶ。成功すると push/pull が認証付きで通る。
    func restoreBackendSession() async {
        guard let supabase, let refresh = defaults.string(forKey: refreshTokenKey) else { return }
        do {
            let remote = try await supabase.refreshSession(refreshToken: refresh)
            await supabase.setAccessToken(remote.accessToken)
            let name = defaults.string(forKey: backendNameKey) ?? session?.displayName ?? "Apple ユーザー"
            persistBackendSession(access: remote.accessToken, refresh: remote.refreshToken, userId: remote.userId, displayName: name)
            provider.persistSession(userId: remote.userId, displayName: name)
            isBackendAuthenticated = true
            let restored = UserSession(userId: remote.userId, displayName: name)
            session = restored
            ensureProfile(for: restored)
            onBackendSignIn?(nil, remote.userId) // 復帰後の同期を促す（old=nil なので移行は走らない）
        } catch {
            // refresh 失敗：トークン失効。ローカルセッションのまま（再ログインが必要）。
            isBackendAuthenticated = false
        }
    }

    /// バックエンド認証成功（Apple / メール / Google 共通）後のセッション確立。
    /// アクセストークン設定・永続化・ローカル識別統一・Profile 整合・移行フックまでを一手に行う。
    private func establishBackendSession(_ remote: SupabaseClient.AuthSession, displayName: String?, oldUserId: UUID?) async {
        await supabase?.setAccessToken(remote.accessToken)
        let name = [displayName, remote.fullName, session?.displayName, remote.email]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "ユーザー"
        persistBackendSession(access: remote.accessToken, refresh: remote.refreshToken, userId: remote.userId, displayName: name)
        provider.persistSession(userId: remote.userId, displayName: name) // ローカル識別も Supabase id に統一
        isBackendAuthenticated = true
        let newSession = UserSession(userId: remote.userId, displayName: name)
        session = newSession
        ensureProfile(for: newSession)
        // 旧ローカルデータの付け替え＋同期を AppEnvironment 側で実行。
        onBackendSignIn?(oldUserId, remote.userId)
    }

    // MARK: - Email OTP（6桁コード）

    /// メールにワンタイムコードを送る。送信できたら true。
    func sendEmailCode(_ email: String) async -> Bool {
        guard let supabase else { return false }
        do {
            try await supabase.sendEmailOTP(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            return true
        } catch { return false }
    }

    /// メールのコードを検証してバックエンドセッションを確立。
    func verifyEmailCode(email: String, code: String) async -> Bool {
        guard let supabase else { return false }
        let addr = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let oldUserId = session?.userId
            let remote = try await supabase.verifyEmailOTP(email: addr, token: code.trimmingCharacters(in: .whitespaces))
            let fallbackName = String(addr.split(separator: "@").first ?? "ユーザー")
            await establishBackendSession(remote, displayName: fallbackName, oldUserId: oldUserId)
            return true
        } catch { return false }
    }

    // MARK: - Google（OAuth via PKCE）

    /// Google でサインイン。ASWebAuthenticationSession で認可 → code を PKCE 交換。成功で true。
    func signInWithGoogle() async -> Bool {
        guard let supabase else { return false }
        let challenge = await supabase.googleAuthorizeURL(redirectTo: "gymnee://auth-callback")
        do {
            let callback = try await webAuth.start(url: challenge.url, callbackScheme: "gymnee")
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty
            else { return false }
            let oldUserId = session?.userId
            let remote = try await supabase.exchangeCodeForSession(authCode: code, codeVerifier: challenge.codeVerifier)
            await establishBackendSession(remote, displayName: nil, oldUserId: oldUserId)
            return true
        } catch { return false }
    }

    private func persistBackendSession(access: String, refresh: String, userId: UUID, displayName: String) {
        defaults.set(access, forKey: accessTokenKey)
        defaults.set(refresh, forKey: refreshTokenKey)
        defaults.set(userId.uuidString, forKey: backendUserIdKey)
        defaults.set(displayName, forKey: backendNameKey)
    }

    private func clearBackendSession() {
        [accessTokenKey, refreshTokenKey, backendUserIdKey, backendNameKey].forEach { defaults.removeObject(forKey: $0) }
        isBackendAuthenticated = false
    }

    /// アカウントを完全に削除する（§7 / App Store 5.1.1(v)）。
    /// リモート接続時は Supabase の `auth.users` を削除（user_id 参照は CASCADE で連鎖削除）。
    /// 失敗しても返り値で通知し、ローカルの識別情報は破棄してサインアウトする。
    @discardableResult
    func deleteAccount() async -> Bool {
        var remoteOK = true
        if let supabase {
            do { try await supabase.deleteAccount() }
            catch { remoteOK = false }
        }
        provider.deleteLocalIdentity()
        clearBackendSession()
        session = nil
        return remoteOK
    }

    // MARK: - Sign in with Apple

    /// `SignInWithAppleButton` の onRequest で呼ぶ。scope と nonce を設定する。
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// `SignInWithAppleButton` の onCompletion で呼ぶ。成功時にセッションを確立する。
    @discardableResult
    func completeSignInWithApple(_ result: Result<ASAuthorization, Error>) async -> Bool {
        guard case let .success(authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        else { return false }

        let displayName = Self.displayName(from: credential.fullName)

        // Supabase 接続時: identityToken を Supabase Auth に渡してリモートセッションを得る。
        if let supabase,
           let tokenData = credential.identityToken,
           let identityToken = String(data: tokenData, encoding: .utf8) {
            do {
                let oldUserId = session?.userId
                let remote = try await supabase.signInWithApple(identityToken: identityToken, nonce: currentNonce)
                await establishBackendSession(remote, displayName: displayName, oldUserId: oldUserId)
                currentNonce = nil
                return true
            } catch {
                // リモート交換に失敗したらローカル経路にフォールバック（オフライン継続）。
            }
        }

        // ローカル経路: Apple ユーザー識別子を決定的にローカル userId へ対応付ける。
        guard let local = try? provider.signInWithApple(userIdentifier: credential.user, displayName: displayName) else {
            return false
        }
        session = local
        ensureProfile(for: local)
        currentNonce = nil
        return true
    }

    // MARK: - Profile

    /// 認証ユーザーに対応する Profile が無ければ作成する。
    private func ensureProfile(for session: UserSession) {
        guard let context else { return }
        let userId = session.userId
        let descriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.id == userId })
        let existing = (try? context.fetch(descriptor))?.first
        if let existing {
            if existing.displayName != session.displayName {
                existing.displayName = session.displayName
                existing.updatedAt = .now
                existing.isDirty = true
            }
        } else {
            let profile = Profile(id: userId, displayName: session.displayName)
            context.insert(profile)
        }
        try? context.save()
    }

    // MARK: - Nonce helpers (Supabase の Apple OIDC 検証に必須)

    private static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        let name = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
