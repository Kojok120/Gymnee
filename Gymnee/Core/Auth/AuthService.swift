import Foundation
import SwiftData
import Observation

/// セッション状態の保持と Profile 行の整合を司る（§6.1）。
/// View は `session` を観測し、未ログインなら Onboarding、ログイン済みなら本体を表示する。
@MainActor
@Observable
final class AuthService {
    private(set) var session: UserSession?
    private let provider: AuthProviding
    private var context: ModelContext?

    var isSignedIn: Bool { session != nil }
    var currentUserId: UUID? { session?.userId }

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

    func signIn(displayName: String) {
        guard let restored = try? provider.signIn(displayName: displayName) else { return }
        session = restored
        ensureProfile(for: restored)
    }

    func signInWithApple() {
        guard let restored = try? provider.signInWithApple() else { return }
        session = restored
        ensureProfile(for: restored)
    }

    func signOut() {
        provider.signOut()
        session = nil
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
}
