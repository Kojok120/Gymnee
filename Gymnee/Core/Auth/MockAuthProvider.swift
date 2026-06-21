import Foundation
import CryptoKit

/// ローカル完結の認証（§9 認証=ローカルで開始）。
/// userId と表示名を UserDefaults に永続化し、再起動後も同一ユーザーを復元する。
/// Supabase 未接続時はこの経路を使い、接続後は `AuthService` が Supabase Auth に委譲する。
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
        persist(id: id, name: name)
        return UserSession(userId: id, displayName: name)
    }

    func signInWithApple(userIdentifier: String, displayName: String?) throws -> UserSession {
        // Apple のユーザー識別子から決定的に UUID を導く（同一 Apple ID → 同一ローカルユーザー）。
        let id = Self.deterministicUUID(from: userIdentifier)
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (trimmed?.isEmpty == false ? trimmed! : nil)
            ?? defaults.string(forKey: displayNameKey)
            ?? "Apple ユーザー"
        persist(id: id, name: name)
        return UserSession(userId: id, displayName: name)
    }

    func signOut() {
        // ローカルデータ（記録）は保持し、セッション識別のみ破棄する設計。
        // userId は保持しておき、再ログインで同じデータに復帰できるようにする。
    }

    func deleteLocalIdentity() {
        // アカウント削除時は保持していた userId・表示名も破棄する（再ログインで復帰させない）。
        defaults.removeObject(forKey: userIdKey)
        defaults.removeObject(forKey: displayNameKey)
    }

    func persistSession(userId: UUID, displayName: String) {
        persist(id: userId, name: displayName)
    }

    private func persist(id: UUID, name: String) {
        defaults.set(id.uuidString, forKey: userIdKey)
        defaults.set(name, forKey: displayNameKey)
    }

    /// 文字列から決定的に UUID を生成（SHA256 の先頭 16 バイト）。
    static func deterministicUUID(from string: String) -> UUID {
        let digest = SHA256.hash(data: Data(string.utf8))
        var bytes = Array(digest.prefix(16))
        // RFC4122 風に version/variant ビットを整える（衝突回避目的ではなく体裁）。
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let t = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                 bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: t)
    }
}
