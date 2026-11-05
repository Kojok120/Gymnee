import Foundation
import Observation

/// 外部連携（#171）。AI（Claude・ChatGPT）の接続・API キー・承認待ちを扱う。
///
/// **サーバーが正**（`connect/` の Worker）。ここは読み取った一覧を画面に渡し、作成・解除・承認を中継するだけ。
/// サインインしていない（ゲスト）ときは何もしない。連携は本人のアカウントのデータを外へ出すため。
@MainActor
@Observable
final class ConnectService {
    struct ScopeLabel: Decodable, Hashable, Sendable {
        let scope: String
        let label: String
    }

    struct AIClient: Decodable, Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let domain: String?
        let scopes: [ScopeLabel]
        let createdAt: String
    }

    struct ApiToken: Decodable, Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let prefix: String
        let scopes: [ScopeLabel]
        let createdAt: String
        let lastUsedAt: String?
    }

    struct Connections: Decodable, Sendable {
        let mcpUrl: String
        let apiBaseUrl: String
        let docsUrl: String
        let aiClients: [AIClient]
        let apiTokens: [ApiToken]
    }

    /// 作った直後の API キー。トークンそのものを見せるのはこの 1 回だけ。
    struct CreatedToken: Decodable, Identifiable, Sendable {
        let id: String
        let name: String
        let token: String
        let scopes: [ScopeLabel]
    }

    struct Pairing: Decodable, Identifiable, Sendable {
        let id: String
        let code: String
        let clientName: String
        let clientDomain: String?
        let redirectHost: String
        let redirectIsLoopback: Bool
        let scopes: [ScopeLabel]
        let expiresAt: String
    }

    enum ConnectError: LocalizedError, Equatable {
        case notSignedIn
        case expired
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "連携を使うにはサインインしてください。"
            case .expired: return "この承認は時間切れです。接続を始めたアプリから、もう一度やり直してください。"
            case let .failed(message): return message
            }
        }
    }

    private(set) var connections: Connections?
    private(set) var isLoading = false
    private(set) var loadError: String?
    /// ユニバーサルリンクで届いた承認待ち。RootView がシートで出す。
    var pendingPairingId: UUID?

    private var client: SupabaseClient?

    func configure(client: SupabaseClient) { self.client = client }

    /// 見本のデータを出しているか（DEBUG の `-gymneeScreen connect*` だけ。製品ビルドでは常に false）。
    private(set) var isShowingFixture = false

    @discardableResult
    private func call(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Data {
        guard let client, await client.isAuthenticated else { throw ConnectError.notSignedIn }
        do {
            return try await client.connectCall(method: method, path: path, body: body)
        } catch let SupabaseClient.SupabaseError.http(status, body) {
            if status == 410 { throw ConnectError.expired }
            if status == 401 { throw ConnectError.notSignedIn }
            let message = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw ConnectError.failed(message ?? "うまくいきませんでした。時間をおいてもう一度試してください。")
        } catch let error as URLError {
            throw ConnectError.failed(error.code == .notConnectedToInternet ? "オフラインです。" : "通信できませんでした。")
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ConnectError.failed("サーバーの答えを読めませんでした。アプリを最新にしてください。")
        }
    }

    func load() async {
        if isShowingFixture { return }
        isLoading = true
        defer { isLoading = false }
        do {
            connections = try Self.decode(Connections.self, try await call("GET", "app/connections"))
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func createToken(name: String, scopes: [String]) async throws -> CreatedToken {
        let data = try await call("POST", "app/tokens", body: ["name": name, "scopes": scopes])
        let created = try Self.decode(CreatedToken.self, data)
        await load()
        return created
    }

    func revokeToken(id: String) async throws {
        try await call("DELETE", "app/tokens/\(id)")
        await load()
    }

    func revokeAIClient(id: String) async throws {
        try await call("DELETE", "app/grants/\(id)")
        await load()
    }

    func pairing(id: UUID) async throws -> Pairing {
        #if DEBUG
        if isShowingFixture { return Self.fixturePairing }
        #endif
        return try Self.decode(Pairing.self, try await call("GET", "app/oauth/pairings/\(id.uuidString.lowercased())"))
    }

    /// 承認か拒否。承認のときは、利用者が残した権限だけを渡す（read は必ず含まれる）。
    func decide(pairingId: UUID, approve: Bool, scopes: [String]) async throws {
        try await call(
            "POST", "app/oauth/pairings/\(pairingId.uuidString.lowercased())",
            body: ["decision": approve ? "approve" : "deny", "scopes": scopes]
        )
        if approve { await load() }
    }

    #if DEBUG
    // MARK: - 見本（`-gymneeScreen connect` / `connect-approve`。ローカルの Debug アプリはサインインできないため）

    static let fixturePairingId = UUID(uuidString: "6F0F4C1E-6B3D-4B5E-9F62-3A3C1D0E7B21")!

    static let fixturePairing = Pairing(
        id: fixturePairingId.uuidString.lowercased(), code: "47", clientName: "Claude", clientDomain: "claude.ai",
        redirectHost: "claude.ai", redirectIsLoopback: false,
        scopes: [
            ScopeLabel(scope: "read", label: "記録・自己ベスト・体重（アプリで記録した分）・パーティの状況を読む"),
            ScopeLabel(scope: "workouts:write", label: "ワークアウトの記録を足す（消す・直すはできない）"),
            ScopeLabel(scope: "coach:write", label: "アプリのコーチ画面にメニューを提案する"),
        ],
        expiresAt: "2026-11-05T12:10:00.000Z"
    )

    func showFixture() {
        isShowingFixture = true
        let read = ScopeLabel(scope: "read", label: "記録・自己ベスト・体重（アプリで記録した分）・パーティの状況を読む")
        let write = ScopeLabel(scope: "workouts:write", label: "ワークアウトの記録を足す（消す・直すはできない）")
        connections = Connections(
            mcpUrl: "https://api.gymnee.app/mcp", apiBaseUrl: "https://api.gymnee.app/v1", docsUrl: "https://gymnee.app/connect/",
            aiClients: [AIClient(id: "g1", name: "Claude", domain: "claude.ai", scopes: [read, write], createdAt: "2026-11-03T10:00:00.000Z")],
            apiTokens: [ApiToken(id: "t1", name: "自宅の Mac", prefix: "gym_pat_Qx3a", scopes: [read], createdAt: "2026-11-01T10:00:00.000Z", lastUsedAt: "2026-11-05T08:00:00.000Z")]
        )
    }
    #endif
}
