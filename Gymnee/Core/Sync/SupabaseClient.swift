import Foundation

/// Supabase REST(PostgREST)/Auth(GoTrue) への薄いクライアント。
/// 外部 SDK を足さず URLSession で実装（依存ゼロ・ビルド単独で通る）。
/// RLS を効かせるため、サインイン後にユーザーのアクセストークンを `setAccessToken` で渡す。
actor SupabaseClient {
    private let config: SupabaseConfig
    private let session: URLSession
    private var accessToken: String?

    init(config: SupabaseConfig, session: URLSession? = nil) {
        self.config = config
        if let session {
            self.session = session
        } else {
            // フレーキーな回線でハングした接続が積み上がらないよう短めのタイムアウトと接続数制限を付ける。
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 15
            cfg.timeoutIntervalForResource = 30
            cfg.waitsForConnectivity = false
            cfg.httpMaximumConnectionsPerHost = 4
            self.session = URLSession(configuration: cfg)
        }
    }

    /// サインイン後のユーザーアクセストークン（JWT）を設定する。未設定時は anon キーのみ。
    func setAccessToken(_ token: String?) {
        self.accessToken = token
    }

    enum SupabaseError: Error, LocalizedError {
        case http(status: Int, body: String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case let .http(status, body): return "Supabase HTTP \(status): \(body)"
            case .invalidResponse: return "Supabase: 不正なレスポンス"
            }
        }
    }

    // MARK: - REST (PostgREST)

    /// upsert（衝突はマージ）。`rows` は JSON 化可能な辞書配列。
    /// `onConflict` を指定すると主キー以外（unique 列）で衝突解決する。
    func upsert(table: String, rows: [[String: Any]], onConflict: String? = nil) async throws {
        guard !rows.isEmpty else { return }
        let query = onConflict.map { "on_conflict=\($0)" }
        var request = restRequest(path: table, query: query)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: rows)
        try await send(request)
    }

    /// APNs デバイストークンを登録（token の unique 制約で衝突解決）。user_id は DB 既定の auth.uid()。
    func registerDeviceToken(_ token: String, platform: String = "ios") async throws {
        try await upsert(table: "device_tokens", rows: [["token": token, "platform": platform]], onConflict: "token")
    }

    /// 指定 id 群を削除。
    func delete(table: String, ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let list = ids.map { $0.uuidString.lowercased() }.joined(separator: ",")
        var request = restRequest(path: table, query: "id=in.(\(list))")
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        try await send(request)
    }

    /// `updated_at` が指定時刻より新しい行を取得（pull の差分取得）。
    func select(table: String, updatedSince: Date?) async throws -> [[String: Any]] {
        var query = "select=*&order=updated_at.asc"
        if let updatedSince {
            let iso = ISO8601DateFormatter.supabase.string(from: updatedSince)
            query += "&updated_at=gt.\(iso)"
        }
        var request = restRequest(path: table, query: query)
        request.httpMethod = "GET"
        let data = try await send(request)
        let json = try JSONSerialization.jsonObject(with: data)
        return (json as? [[String: Any]]) ?? []
    }

    // MARK: - Auth (GoTrue)

    /// Sign in with Apple の identityToken を Supabase Auth に渡してセッションを得る。
    /// 返り値からアクセストークン・ユーザー id を取り出す。
    struct AuthSession: Sendable {
        let accessToken: String
        let refreshToken: String
        let userId: UUID
        let email: String?
    }

    func signInWithApple(identityToken: String, nonce: String?) async throws -> AuthSession {
        var request = authRequest(path: "token", query: "grant_type=id_token")
        request.httpMethod = "POST"
        var body: [String: Any] = ["provider": "apple", "id_token": identityToken]
        if let nonce { body["nonce"] = nonce }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(request)
        return try Self.parseAuthSession(data)
    }

    /// refresh_token でアクセストークンを更新（再起動後のセッション復元に使う）。
    func refreshSession(refreshToken: String) async throws -> AuthSession {
        var request = authRequest(path: "token", query: "grant_type=refresh_token")
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        let data = try await send(request)
        return try Self.parseAuthSession(data)
    }

    /// 表示名でユーザー（profiles）を検索する（相互フォローの相手探し）。
    struct RemoteProfile: Sendable, Identifiable {
        let id: UUID
        let displayName: String
    }

    func searchProfiles(nameQuery: String, excluding selfId: UUID?, limit: Int = 20) async throws -> [RemoteProfile] {
        let trimmed = nameQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let pattern = "*\(trimmed)*".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? trimmed
        var query = "select=id,display_name&display_name=ilike.\(pattern)&limit=\(limit)"
        if let selfId { query += "&id=neq.\(selfId.uuidString.lowercased())" }
        var request = restRequest(path: "profiles", query: query)
        request.httpMethod = "GET"
        let data = try await send(request)
        let rows = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return rows.compactMap { row in
            guard let idStr = row["id"] as? String, let id = UUID(uuidString: idStr) else { return nil }
            let name = (row["display_name"] as? String) ?? "ユーザー"
            return RemoteProfile(id: id, displayName: name)
        }
    }

    /// アカウント削除 RPC（auth.users 削除 → CASCADE）。要ユーザートークン。
    func deleteAccount() async throws {
        var request = restRequest(path: "rpc/delete_account")
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [String: Any]())
        try await send(request)
    }

    // MARK: - Request building

    private func restRequest(path: String, query: String? = nil) -> URLRequest {
        var components = URLComponents(url: config.url.appendingPathComponent("rest/v1/\(path)"), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = query
        return signed(URLRequest(url: components.url!))
    }

    private func authRequest(path: String, query: String? = nil) -> URLRequest {
        var components = URLComponents(url: config.url.appendingPathComponent("auth/v1/\(path)"), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = query
        return signed(URLRequest(url: components.url!))
    }

    private func signed(_ request: URLRequest) -> URLRequest {
        var req = request
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // anon / publishable key は apikey ヘッダで送る。
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        // Authorization は「ユーザーのアクセストークン(JWT)がある時だけ」付ける。
        // 新方式の publishable key は JWT ではないため Bearer には載せない（匿名は apikey だけで anon ロール）。
        if let accessToken {
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private static func parseAuthSession(_ data: Data) throws -> AuthSession {
        guard
            let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = dict["access_token"] as? String,
            let refreshToken = dict["refresh_token"] as? String
        else { throw SupabaseError.invalidResponse }
        let user = dict["user"] as? [String: Any]
        let userId = (user?["id"] as? String).flatMap(UUID.init) ?? UUID()
        let email = user?["email"] as? String
        return AuthSession(accessToken: accessToken, refreshToken: refreshToken, userId: userId, email: email)
    }
}

extension ISO8601DateFormatter {
    /// PostgREST と突合するための UTC ISO8601（小数秒つき）。
    static let supabase: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 小数秒なしの ISO8601（PostgREST が小数秒を返さない場合のフォールバック）。
    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
