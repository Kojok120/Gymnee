import Foundation

/// ローカル完結のモック認証（§9 認証=モック/ローカルで開始）。
/// userId と表示名を UserDefaults に永続化し、再起動後も同一ユーザーを復元する。
/// Sign in with Apple / Supabase Auth は同 `AuthProviding` 準拠で後日差し替える。
final class MockAuthProvider: AuthProviding, @unchecked Sendable {
    private let defaults: UserDefaults
    private let userIdKey = "gymnee.auth.userId"
    private let displayNameKey = "gymnee.auth.displayName"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restoreSession() -> UserSession? {
        guard
            let idString = defaults.string(forKey: userIdKey),
            let id = UUID(uuidString: idString)
        else { return nil }
        let name = defaults.string(forKey: displayNameKey) ?? "ゲスト"
        return UserSession(userId: id, displayName: name)
    }

    func signIn(displayName: String) throws -> UserSession {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "ゲスト" : trimmed
        // 既存ユーザーがいれば id を維持、なければ新規採番。
        let id = (defaults.string(forKey: userIdKey).flatMap(UUID.init)) ?? UUID()
        defaults.set(id.uuidString, forKey: userIdKey)
        defaults.set(name, forKey: displayNameKey)
        return UserSession(userId: id, displayName: name)
    }

    func signInWithApple() throws -> UserSession {
        // v0: 実 SiwA は有償アカウント必須のためモックに委譲。
        try signIn(displayName: "Apple ユーザー")
    }

    func signOut() {
        // ローカルデータ（記録）は保持し、セッション識別のみ破棄する設計。
        // userId は保持しておき、再ログインで同じデータに復帰できるようにする。
    }
}
