import Foundation

/// 認証済みセッション。
struct UserSession: Equatable, Sendable {
    let userId: UUID
    var displayName: String
}

/// 認証プロバイダ抽象（§6.1 / §9 認証は protocol 化して後差し込み）。
/// ローカルでは `MockAuthProvider`。Supabase Auth 経由の Sign in with Apple は `AuthService` 側で
/// SupabaseClient と協調して扱う（リモート未接続時は本 protocol のローカル経路にフォールバック）。
protocol AuthProviding: AnyObject, Sendable {
    /// 永続化された前回セッションを復元する（なければ nil）。
    func restoreSession() -> UserSession?
    /// 表示名を指定してサインイン（手動・ローカル）。
    func signIn(displayName: String) throws -> UserSession
    /// 実 Apple クレデンシャルをローカルセッションへ対応付ける（リモート未接続時の経路）。
    /// 同一 Apple ユーザーは常に同じローカル userId に解決される（決定的）。
    func signInWithApple(userIdentifier: String, displayName: String?) throws -> UserSession
    /// サインアウト（ローカルデータは保持）。
    func signOut()
    /// ローカルの認証情報（userId・表示名）を破棄する。アカウント削除時に呼ぶ。
    func deleteLocalIdentity()
    /// 指定の userId・表示名を永続化する（Supabase サインイン後にローカル識別を統一するため）。
    func persistSession(userId: UUID, displayName: String)
}
