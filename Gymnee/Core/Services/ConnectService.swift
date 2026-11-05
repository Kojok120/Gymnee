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

    /// Slack / Discord / 汎用 Webhook の送り先（#171 の 2 段目）。
    struct Destination: Decodable, Identifiable, Hashable, Sendable {
        let id: String
        let kind: String
        let label: String
        let events: [String]
        /// 止まっていればその理由（消された・続けて届かなかった）。
        let disabledReason: String?
        let lastDeliveredAt: String?
        let createdAt: String

        static let workoutCompleted = "workout.completed"
        static let weeklySummary = "weekly.summary"

        var kindLabel: String {
            switch kind {
            case "slack": return "Slack"
            case "discord": return "Discord"
            default: return "Webhook"
            }
        }
    }

    /// LINE の連携（#171 の 3 段目）。
    struct Line: Decodable, Hashable, Sendable {
        let configured: Bool
        let linked: Bool
        let notifyMode: String?
        let notifyHour: Int?
        let linkedAt: String?
        let addFriendUrl: String?

        static let unavailable = Line(configured: false, linked: false, notifyMode: nil, notifyHour: nil, linkedAt: nil, addFriendUrl: nil)
    }

    /// LINE の通知の出し方。サーバーの line_links.notify_mode と同じ値。
    enum LineNotifyMode: String, CaseIterable, Identifiable, Sendable {
        case off, lapse, daily, dailyMenu = "daily_menu"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: return "送らない"
            case .lapse: return "途切れそうなときだけ"
            case .daily: return "毎日"
            case .dailyMenu: return "毎日＋メニュー提案"
            }
        }
    }

    struct LinkCode: Decodable, Sendable {
        let code: String
        let expiresAt: String
        let openUrl: String
        let addFriendUrl: String
    }

    struct Providers: Decodable, Hashable, Sendable {
        let slack: Bool
        let discord: Bool
    }

    struct Connections: Decodable, Sendable {
        let mcpUrl: String
        let apiBaseUrl: String
        let docsUrl: String
        let aiClients: [AIClient]
        let apiTokens: [ApiToken]
        let destinations: [Destination]
        let providers: Providers
        let line: Line

        init(mcpUrl: String, apiBaseUrl: String, docsUrl: String, aiClients: [AIClient], apiTokens: [ApiToken],
             destinations: [Destination] = [], providers: Providers = Providers(slack: false, discord: false), line: Line = .unavailable) {
            self.mcpUrl = mcpUrl
            self.apiBaseUrl = apiBaseUrl
            self.docsUrl = docsUrl
            self.aiClients = aiClients
            self.apiTokens = apiTokens
            self.destinations = destinations
            self.providers = providers
            self.line = line
        }

        private enum CodingKeys: String, CodingKey { case mcpUrl, apiBaseUrl, docsUrl, aiClients, apiTokens, destinations, providers, line }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mcpUrl = try c.decode(String.self, forKey: .mcpUrl)
            apiBaseUrl = try c.decode(String.self, forKey: .apiBaseUrl)
            docsUrl = try c.decode(String.self, forKey: .docsUrl)
            aiClients = try c.decode([AIClient].self, forKey: .aiClients)
            apiTokens = try c.decode([ApiToken].self, forKey: .apiTokens)
            // 送り先は 2 段目で足した。古いサーバーが返さなくても一覧は出す。
            destinations = try c.decodeIfPresent([Destination].self, forKey: .destinations) ?? []
            providers = try c.decodeIfPresent(Providers.self, forKey: .providers) ?? Providers(slack: false, discord: false)
            line = try c.decodeIfPresent(Line.self, forKey: .line) ?? .unavailable
        }
    }

    /// 送り先を足した結果。汎用 Webhook の署名の鍵を見せるのはこの 1 回だけ。
    struct CreatedDestination: Decodable, Sendable {
        let destination: Destination
        let signingSecret: String?
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

    // MARK: - LINE

    /// 連携コードを作る。返る URL を開くと、LINE のトークに「連携 123456」が入った状態になる。
    func lineLinkCode() async throws -> LinkCode {
        try Self.decode(LinkCode.self, try await call("POST", "app/line/link-code"))
    }

    func updateLine(mode: LineNotifyMode? = nil, hour: Int? = nil) async throws {
        var body: [String: Any] = [:]
        if let mode { body["notifyMode"] = mode.rawValue }
        if let hour { body["notifyHour"] = hour }
        try await call("PATCH", "app/line", body: body)
        await load()
    }

    func unlinkLine() async throws {
        try await call("DELETE", "app/line")
        await load()
    }

    // MARK: - 送り先（Slack / Discord / 汎用 Webhook）

    func addDestination(url: String, label: String?) async throws -> CreatedDestination {
        var body: [String: Any] = ["url": url]
        if let label, !label.isEmpty { body["label"] = label }
        let created = try Self.decode(CreatedDestination.self, try await call("POST", "app/destinations", body: body))
        await load()
        return created
    }

    func updateDestination(id: String, events: [String]) async throws {
        try await call("PATCH", "app/destinations/\(id)", body: ["events": events])
        await load()
    }

    func resumeDestination(id: String) async throws {
        try await call("POST", "app/destinations/\(id)/resume")
        await load()
    }

    func deleteDestination(id: String) async throws {
        try await call("DELETE", "app/destinations/\(id)")
        await load()
    }

    private struct StartResponse: Decodable { let url: String; let callbackScheme: String }

    /// 「Slack に追加」「Discord に追加」で開く認可の URL。
    func chatConnectURL(provider: String) async throws -> (url: URL, callbackScheme: String) {
        let res = try Self.decode(StartResponse.self, try await call("GET", "app/\(provider)/start"))
        guard let url = URL(string: res.url) else { throw ConnectError.failed("つなぐ画面を開けませんでした。") }
        return (url, res.callbackScheme)
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
            apiTokens: [ApiToken(id: "t1", name: "自宅の Mac", prefix: "gym_pat_Qx3a", scopes: [read], createdAt: "2026-11-01T10:00:00.000Z", lastUsedAt: "2026-11-05T08:00:00.000Z")],
            destinations: [
                Destination(id: "d1", kind: "slack", label: "#筋トレ部（ココバル）", events: [Destination.workoutCompleted, Destination.weeklySummary],
                            disabledReason: nil, lastDeliveredAt: "2026-11-05T09:00:00.000Z", createdAt: "2026-11-02T10:00:00.000Z"),
                Destination(id: "d2", kind: "discord", label: "Discord（ジム仲間）", events: [Destination.weeklySummary],
                            disabledReason: "送り先が見つからない（チャンネルか Webhook が消された）", lastDeliveredAt: nil, createdAt: "2026-11-03T10:00:00.000Z"),
            ],
            providers: Providers(slack: true, discord: true),
            line: Line(configured: true, linked: true, notifyMode: "daily_menu", notifyHour: 7, linkedAt: "2026-11-05T22:00:00.000Z", addFriendUrl: "https://line.me/R/ti/p/@gymnee")
        )
    }
    #endif
}
