import Foundation

/// 認証済みセッション。
struct UserSession: Equatable, Sendable {
    let userId: UUID
    var displayName: String
}

/// 認証プロバイダ抽象（§9 認証は protocol 化して後差し込み）。
/// ローカルでは `MockAuthProvider`、将来 Sign in with Apple / Supabase Auth 実装を同 protocol で差し替える。
protocol AuthProviding: AnyObject, Sendable {
    /// 永続化された前回セッションを復元する（なければ nil）。
    func restoreSession() -> UserSession?
    /// 表示名を指定してサインイン（モック）。
    func signIn(displayName: String) throws -> UserSession
    /// Sign in with Apple 経路（v0 はモックに委譲、実装は有償アカウント整備後）。
    func signInWithApple() throws -> UserSession
    /// サインアウト（ローカルデータは保持）。
    func signOut()
}
