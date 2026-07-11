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

    /// バックエンド(Supabase)で認証済みか（トークン保持中。匿名セッションを含む）。
    private(set) var isBackendAuthenticated = false
    /// 現在のバックエンドセッションが匿名（is_anonymous・identity 未リンク）か。
    private(set) var isAnonymousBackendSession = false
    /// バックエンドサインイン成功時のフック（旧 userId, 新 userId）。AppEnvironment が移行＋同期を差し込む。
    /// oldUserId は IdentityAdoptionPolicy で選別済み（恒久アカウント切替では nil）。
    @ObservationIgnored var onBackendSignIn: ((_ oldUserId: UUID?, _ newUserId: UUID) -> Void)?
    /// ゲスト/匿名期間から本人性のあるアカウントへ確定した直後のフック（onBackendSignIn の後に発火）。
    /// 同一恒久アカウントの再認証・別端末での既存アカウントサインインでは発火しない。
    /// （Fix C でプロフィール生成の差し込み先に使う。現状 Fix A では未配線。）
    @ObservationIgnored var onBecamePermanent: ((_ userId: UUID) -> Void)?

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// OAuth(Google) のブラウザ往復用（ASWebAuthenticationSession ラッパ）。
    @ObservationIgnored private let webAuth = WebAuthSession()
    /// 匿名サインアップの多重実行ガード（起動時とゲスト開始時が重なり得る）。
    @ObservationIgnored private var anonymousSignUpInFlight = false
    /// 匿名 uid へのメール紐付け（requestEmailChange）を送った宛先。verify の検証タイプ判定に使う。
    @ObservationIgnored private var pendingEmailLinkAddress: String?
    private let accessTokenKey = "gymnee.supabase.accessToken"
    private let refreshTokenKey = "gymnee.supabase.refreshToken"
    private let backendUserIdKey = "gymnee.supabase.userId"
    private let backendNameKey = "gymnee.supabase.displayName"
    private let backendIsAnonymousKey = "gymnee.supabase.isAnonymous"

    var isSignedIn: Bool { session != nil }
    var currentUserId: UUID? { session?.userId }
    /// バックエンド(Supabase)が構成済みで、メール/Google サインインが使えるか。
    var isBackendAvailable: Bool { supabase != nil }
    /// 本人性のあるアカウント（Apple/Google/メールを identity として持つ）でサインイン済みか。
    /// 匿名セッションは含まない。ソーシャル・AI 等「サインイン済み」を要求する UI はこれで判定する。
    var isPermanentAccount: Bool { isBackendAuthenticated && !isAnonymousBackendSession }
    /// 永続化済みのバックエンドセッションがあるか（再起動後の復元判定／Settings 表示用）。
    var hasPersistedBackendSession: Bool { Keychain.get(refreshTokenKey) != nil }

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
        guard let client else { return }
        // トークン期限切れ(401)時にクライアントが自動更新したら、新トークンを Keychain に保存し直す
        // （Supabase の refresh_token はローテーションするため、保存しないと次回起動で失効する）。
        Task {
            await client.setTokenRefreshHandler { [weak self] access, refresh in
                Task { @MainActor in self?.persistRefreshedTokens(access: access, refresh: refresh) }
            }
        }
    }

    /// クライアントの自動トークン更新を Keychain へ反映（access/refresh とも保存）。
    private func persistRefreshedTokens(access: String, refresh: String) {
        Keychain.set(access, for: accessTokenKey)
        Keychain.set(refresh, for: refreshTokenKey)
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
        // ゲスト開始直後に匿名セッションを確立する（安定 uid の発行。オフラインなら次回起動で再試行）。
        Task { await ensureAnonymousSession() }
    }

    func signOut() {
        provider.signOut()
        clearBackendSession()
        let client = supabase
        Task { await client?.setSession(accessToken: nil, refreshToken: nil) }
        // ローカル識別（userId）も破棄して、次回ゲストを新規 uid で開始する。
        // 旧アカウント uid をローカル識別に残すと、次の別アカウントサインイン時に
        // 「直前セッション＝旧アカウント」となり付け替え判定の対象に載ってしまう
        // （IdentityAdoptionPolicy が恒久アカウントを弾く前提を崩さないための恒久策）。
        // ローカルの記録自体は保持され、同一アカウントへ再サインインすれば再び表示される。
        provider.deleteLocalIdentity()
        session = nil
    }

    /// 再起動後にバックエンドセッションを復元する（refresh_token でアクセストークンを更新）。
    /// GymneeApp の起動時 task から呼ぶ。成功すると push/pull が認証付きで通る。
    func restoreBackendSession() async {
        guard let supabase, let refresh = Keychain.get(refreshTokenKey) else { return }
        do {
            let remote = try await supabase.refreshSession(refreshToken: refresh)
            await supabase.setSession(accessToken: remote.accessToken, refreshToken: remote.refreshToken)
            let name = defaults.string(forKey: backendNameKey) ?? session?.displayName ?? "Apple ユーザー"
            persistBackendSession(access: remote.accessToken, refresh: remote.refreshToken, userId: remote.userId, displayName: name, isAnonymous: remote.isAnonymous)
            provider.persistSession(userId: remote.userId, displayName: name)
            isBackendAuthenticated = true
            isAnonymousBackendSession = remote.isAnonymous
            let restored = UserSession(userId: remote.userId, displayName: name)
            session = restored
            ensureProfile(for: restored)
            onBackendSignIn?(nil, remote.userId) // 復帰後の同期を促す（old=nil なので移行は走らない）
        } catch {
            // refresh 失敗：トークン失効。ローカルセッションのまま（再ログインが必要）。
            isBackendAuthenticated = false
        }
    }

    /// バックエンド未認証のゲストに匿名セッションを確立する（安定 uid の即時発行・Phase 2）。
    /// 起動時（bootstrapBackend）とゲスト開始（オンボーディング完了）直後に呼ぶ。
    /// オフライン・レート制限等で失敗してもローカルのみで継続し、次回起動時に再試行される。
    /// ローカルゲスト uid のデータは establishBackendSession 経由で匿名 uid へ 1 回だけ付け替わり、
    /// 以後のサインインは identity リンク（uid 不変）になるため付け替えは二度と走らない。
    func ensureAnonymousSession() async {
        guard let supabase,
              !isBackendAuthenticated,
              !hasPersistedBackendSession,
              session != nil,          // オンボーディング完了（ローカルセッション確立）後のみ
              !anonymousSignUpInFlight else { return }
        anonymousSignUpInFlight = true
        defer { anonymousSignUpInFlight = false }
        do {
            let remote = try await supabase.signInAnonymously()
            await establishBackendSession(remote, displayName: session?.displayName ?? "ゲスト", previousSession: session)
        } catch {
            // ネットワーク断・レート制限（30件/時/IP）等。オフラインファーストのまま継続。
        }
    }

    /// バックエンド認証成功（Apple / メール / Google / 匿名共通）後のセッション確立。
    /// アクセストークン設定・永続化・ローカル識別統一・Profile 整合・移行フックまでを一手に行う。
    /// 直前セッションのローカルデータを引き継ぐか（付け替え）は IdentityAdoptionPolicy で判定する
    /// （永続値は persistBackendSession で上書きされる前にここで読む）。
    private func establishBackendSession(_ remote: SupabaseClient.AuthSession, displayName: String?, previousSession: UserSession?) async {
        let persistedUserId = defaults.string(forKey: backendUserIdKey).flatMap(UUID.init)
        let persistedIsAnonymous = defaults.bool(forKey: backendIsAnonymousKey)
        let adoptableOldUserId: UUID? = IdentityAdoptionPolicy.shouldAdopt(
            oldUserId: previousSession?.userId,
            newUserId: remote.userId,
            persistedBackendUserId: persistedUserId,
            persistedBackendIsAnonymous: persistedIsAnonymous
        ) ? previousSession?.userId : nil

        await supabase?.setSession(accessToken: remote.accessToken, refreshToken: remote.refreshToken)
        let name = [displayName, remote.fullName, previousSession?.displayName, remote.email]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "ユーザー"
        persistBackendSession(access: remote.accessToken, refresh: remote.refreshToken, userId: remote.userId, displayName: name, isAnonymous: remote.isAnonymous)
        provider.persistSession(userId: remote.userId, displayName: name) // ローカル識別も Supabase id に統一
        isBackendAuthenticated = true
        isAnonymousBackendSession = remote.isAnonymous
        let newSession = UserSession(userId: remote.userId, displayName: name)
        session = newSession
        ensureProfile(for: newSession)
        // 旧ローカルデータの付け替え＋同期を AppEnvironment 側で実行（恒久アカウント切替では nil）。
        onBackendSignIn?(adoptableOldUserId, remote.userId)
        // ゲスト/匿名期間 → 本人アカウント確定の遷移でのみ発火（付け替え後＝記録が新 uid 所有になった後）。
        // - リンクによる本登録化: persistedIsAnonymous（uid 不変・adoptableOld は nil）
        // - ゲスト期間データの採用を伴うサインイン: adoptableOldUserId != nil
        // 同一恒久アカウントの再認証（wasPermanentSameAccount）では発火しない。
        let wasPermanentSameAccount = (persistedUserId == remote.userId && !persistedIsAnonymous)
        if !remote.isAnonymous, !wasPermanentSameAccount, adoptableOldUserId != nil || persistedIsAnonymous {
            onBecamePermanent?(remote.userId)
        }
    }

    /// 匿名セッションから既存アカウントへ切り替える直前の後始末（returning-user・マージ例外）。
    /// サーバー側の匿名ユーザーを削除して、同一 record id のローカル行を新アカウントとして
    /// 再 push できるようにする（残すと PK 衝突→RLS 拒否で outbox が詰まる）。
    /// 削除できなかったら false（呼び出し側は付け替えを見送る）。匿名はこの端末しかトークンを
    /// 持たず、公開投稿・フォロー・コメント不可（RLS 0031）のため削除で失われるものは無い。
    private func cleanUpAnonymousBeforeSwitch() async -> Bool {
        guard isBackendAuthenticated, isAnonymousBackendSession, let supabase else { return true }
        do { try await supabase.deleteAccount(); return true } catch { return false }
    }

    // MARK: - Email OTP（6桁コード）

    /// メールにワンタイムコードを送る。送信できたら true。
    /// 匿名セッション中は「メールを現在の uid に紐付ける」（email_change・uid 不変の本登録化）を先に試し、
    /// 既存アカウントのメール（email_exists）なら通常のサインイン OTP に切り替える（returning-user）。
    func sendEmailCode(_ email: String) async -> Bool {
        guard let supabase else { return false }
        let addr = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if isBackendAuthenticated, isAnonymousBackendSession {
            do {
                try await supabase.requestEmailChange(to: addr)
                pendingEmailLinkAddress = addr
                return true
            } catch where SupabaseClient.authErrorCode(error) == "email_exists" {
                // 既存アカウントのメール → 通常サインインへフォールスルー（verify 後に匿名を後始末）。
            } catch { return false }
        }
        pendingEmailLinkAddress = nil
        do {
            try await supabase.sendEmailOTP(email: addr)
            return true
        } catch { return false }
    }

    /// メールのコードを検証してバックエンドセッションを確立。
    func verifyEmailCode(email: String, code: String) async -> Bool {
        guard let supabase else { return false }
        let addr = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = code.trimmingCharacters(in: .whitespaces)
        let fallbackName = String(addr.split(separator: "@").first ?? "ユーザー")
        let previous = session
        do {
            if pendingEmailLinkAddress == addr {
                // 匿名 uid へのメール紐付けの確定（uid 不変＝付け替え不要）。
                let remote = try await supabase.verifyEmailChange(email: addr, token: token)
                pendingEmailLinkAddress = nil
                await establishBackendSession(remote, displayName: fallbackName, previousSession: previous)
                return true
            }
            let remote = try await supabase.verifyEmailOTP(email: addr, token: token)
            // 匿名セッションからの切替なら、サーバー側の匿名ユーザーを後始末してから引き継ぐ。
            let cleaned = await cleanUpAnonymousBeforeSwitch()
            await establishBackendSession(remote, displayName: fallbackName, previousSession: cleaned ? previous : nil)
            return true
        } catch { return false }
    }

    // MARK: - Google（OAuth via PKCE）

    /// Google でサインイン。ASWebAuthenticationSession で認可 → code を PKCE 交換。成功で true。
    /// 匿名セッション中は identity リンク（uid 不変）の authorize URL を先に試し、
    /// リンク不可（既に別アカウントへリンク済み等。callback に error が載る）なら通常サインインへ。
    func signInWithGoogle() async -> Bool {
        guard let supabase else { return false }
        let previous = session
        if isBackendAuthenticated, isAnonymousBackendSession {
            do {
                let challenge = try await supabase.linkGoogleAuthorizeURL(redirectTo: "gymnee://auth-callback")
                let callback = try await webAuth.start(url: challenge.url, callbackScheme: "gymnee")
                if let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty {
                    let remote = try await supabase.exchangeCodeForSession(authCode: code, codeVerifier: challenge.codeVerifier)
                    await establishBackendSession(remote, displayName: nil, previousSession: previous)
                    return true
                }
                // code 無し＝リンク失敗（identity_already_exists 等）。通常サインインでリカバリ。
            } catch {
                // ユーザーキャンセル・通信失敗。匿名のまま（再試行可能）。
                return false
            }
        }
        let challenge = await supabase.googleAuthorizeURL(redirectTo: "gymnee://auth-callback")
        do {
            let callback = try await webAuth.start(url: challenge.url, callbackScheme: "gymnee")
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty
            else { return false }
            let remote = try await supabase.exchangeCodeForSession(authCode: code, codeVerifier: challenge.codeVerifier)
            // 匿名セッションからの切替なら、サーバー側の匿名ユーザーを後始末してから引き継ぐ。
            let cleaned = await cleanUpAnonymousBeforeSwitch()
            await establishBackendSession(remote, displayName: nil, previousSession: cleaned ? previous : nil)
            return true
        } catch { return false }
    }

    private func persistBackendSession(access: String, refresh: String, userId: UUID, displayName: String, isAnonymous: Bool) {
        // トークンは Keychain（端末外へ出ない）。非機微の id/表示名/匿名フラグは UserDefaults。
        // 匿名フラグは「直前セッションが恒久アカウントか」の付け替え判定（IdentityAdoptionPolicy）に使う。
        Keychain.set(access, for: accessTokenKey)
        Keychain.set(refresh, for: refreshTokenKey)
        defaults.set(userId.uuidString, forKey: backendUserIdKey)
        defaults.set(displayName, forKey: backendNameKey)
        defaults.set(isAnonymous, forKey: backendIsAnonymousKey)
    }

    private func clearBackendSession() {
        Keychain.delete(accessTokenKey)
        Keychain.delete(refreshTokenKey)
        [backendUserIdKey, backendNameKey, backendIsAnonymousKey].forEach { defaults.removeObject(forKey: $0) }
        isBackendAuthenticated = false
        isAnonymousBackendSession = false
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
        let previous = session

        // Supabase 接続時: identityToken を Supabase Auth に渡してリモートセッションを得る。
        if let supabase,
           let tokenData = credential.identityToken,
           let identityToken = String(data: tokenData, encoding: .utf8) {
            // 匿名セッション中は identity リンク（uid 不変＝付け替え不要）を最優先で試す。
            if isBackendAuthenticated, isAnonymousBackendSession {
                do {
                    let remote = try await supabase.linkAppleIdentity(identityToken: identityToken, nonce: currentNonce)
                    await establishBackendSession(remote, displayName: displayName, previousSession: previous)
                    currentNonce = nil
                    return true
                } catch where SupabaseClient.authErrorCode(error) == "identity_already_exists" {
                    // この Apple ID は既存アカウントのもの（returning-user）。通常サインインへフォールスルー。
                } catch {
                    // 通信等の一時失敗。匿名のまま失敗を返す（再試行可能。ローカル経路に落とすと
                    // 決定的ローカル uid が生まれて匿名 uid と分裂するため落とさない）。
                    currentNonce = nil
                    return false
                }
            }
            do {
                let remote = try await supabase.signInWithApple(identityToken: identityToken, nonce: currentNonce)
                // 匿名セッションからの切替なら、サーバー側の匿名ユーザーを後始末してから引き継ぐ。
                let cleaned = await cleanUpAnonymousBeforeSwitch()
                await establishBackendSession(remote, displayName: displayName, previousSession: cleaned ? previous : nil)
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
        // 付け替え判定は establishBackendSession と同じ Policy（永続値はセッション確立前に読む）。
        let persistedUserId = defaults.string(forKey: backendUserIdKey).flatMap(UUID.init)
        let persistedIsAnonymous = defaults.bool(forKey: backendIsAnonymousKey)
        let adopt = IdentityAdoptionPolicy.shouldAdopt(
            oldUserId: previous?.userId,
            newUserId: local.userId,
            persistedBackendUserId: persistedUserId,
            persistedBackendIsAnonymous: persistedIsAnonymous
        )
        session = local
        ensureProfile(for: local)
        currentNonce = nil
        // ゲスト等の旧ローカル uid からこの決定的 uid へ変わった場合もデータを付け替える
        // （バックエンド経路と同じフック。ここを通さないとゲスト期間の記録が孤児化する）。
        if adopt {
            onBackendSignIn?(previous?.userId, local.userId)
        }
        return true
    }

    // MARK: - Profile

    /// 表示名を更新する（セッション・Profile・ローカル永続を整合）。Profile の同期は呼び出し側で enqueue する。
    func updateDisplayName(_ name: String) {
        guard let current = session else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != current.displayName else { return }
        let updated = UserSession(userId: current.userId, displayName: trimmed)
        session = updated
        provider.persistSession(userId: current.userId, displayName: trimmed)
        if isBackendAuthenticated { defaults.set(trimmed, forKey: backendNameKey) }
        ensureProfile(for: updated)
    }

    /// アバター画像をストレージへアップロードし、Profile.avatar_url を更新する。
    /// 返り値はキャッシュ無効化用のバージョン付き公開URL（同期は呼び出し側で enqueue）。
    func uploadAvatar(_ jpeg: Data) async -> String? {
        guard let supabase, isBackendAuthenticated, let uid = currentUserId else { return nil }
        do {
            let base = try await supabase.uploadAvatar(userId: uid, jpeg: jpeg)
            let versioned = base + "?v=\(Int(Date().timeIntervalSince1970))"
            if let context {
                let descriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.id == uid })
                if let profile = (try? context.fetch(descriptor))?.first {
                    profile.avatarURL = versioned
                    profile.updatedAt = .now
                    profile.isDirty = true
                    try? context.save()
                }
            }
            return versioned
        } catch {
            return nil
        }
    }

    /// 写真をバケットへアップロードし、参照("bucket/path")を返す（progress-photos / visit-photos）。
    func uploadPhoto(bucket: String, filename: String, jpeg: Data) async -> String? {
        guard let supabase, isBackendAuthenticated, let uid = currentUserId else { return nil }
        let path = "\(uid.uuidString.lowercased())/\(filename)"
        return try? await supabase.uploadPhoto(bucket: bucket, path: path, jpeg: jpeg)
    }

    /// 参照("bucket/path")から写真バイト列を取得（端末ローカルに無い時のフォールバック用）。
    func downloadPhoto(ref: String) async -> Data? {
        guard let supabase, isBackendAuthenticated else { return nil }
        return try? await supabase.downloadPhoto(ref: ref)
    }

    /// AI ワークアウト計画（Edge Function 経由）。未構成/未認証/失敗時は nil（呼び出し側で「準備中」）。
    func planWorkouts(days: [String], routines: [String], weeklyGoal: Int, events: [[String: Any]], history: [[String: Any]], recovery: [[String: Any]], condition: [String: Any] = [:], messages: [[String: String]] = [], currentPlan: [[String: Any]] = []) async -> SupabaseClient.PlanResult? {
        guard let supabase, isBackendAuthenticated else { return nil }
        return try? await supabase.planWorkouts(days: days, routines: routines, weeklyGoal: weeklyGoal, events: events, history: history, recovery: recovery, condition: condition, messages: messages, currentPlan: currentPlan)
    }

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
