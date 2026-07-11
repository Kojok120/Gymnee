import Foundation
import CryptoKit
import Security

/// Supabase REST(PostgREST)/Auth(GoTrue) への薄いクライアント。
/// 外部 SDK を足さず URLSession で実装（依存ゼロ・ビルド単独で通る）。
/// RLS を効かせるため、サインイン後にユーザーのアクセストークンを `setAccessToken` で渡す。
actor SupabaseClient {
    private let config: SupabaseConfig
    private let session: URLSession
    /// Edge Function（AI計画など応答が遅い呼び出し）用の長タイムアウト session。
    /// REST 用の短い設定（request 15s / resource 30s）を LLM 呼び出しへ適用すると
    /// 生成に時間がかかった時に常に打ち切られるため分離する。
    private let functionsSession: URLSession
    private var accessToken: String?
    /// 401(JWT expired)時に自動でアクセストークンを更新するための refresh_token。
    private var refreshToken: String?
    /// トークン自動更新時の永続化フック（AuthService が Keychain に保存。refresh はローテーションするため必須）。
    private var onTokenRefresh: (@Sendable (String, String) -> Void)?

    init(config: SupabaseConfig, session: URLSession? = nil) {
        self.config = config
        if let session {
            self.session = session
            self.functionsSession = session
        } else {
            // フレーキーな回線でハングした接続が積み上がらないよう短めのタイムアウトと接続数制限を付ける。
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 15
            cfg.timeoutIntervalForResource = 30
            cfg.waitsForConnectivity = false
            cfg.httpMaximumConnectionsPerHost = 4
            self.session = URLSession(configuration: cfg)
            // Edge Function 用（サーバ側は最悪 ~51s で必ず返す設定なので、それより長く待つ）。
            let fnCfg = URLSessionConfiguration.default
            fnCfg.timeoutIntervalForRequest = 60
            fnCfg.timeoutIntervalForResource = 90
            fnCfg.waitsForConnectivity = false
            self.functionsSession = URLSession(configuration: fnCfg)
        }
    }

    /// ユーザートークンを保持しているか（＝RLS を通る認証付きリクエストが可能か）。
    /// 同期エンジンが「ゲスト期間は送受信しない」判定に使う。
    var isAuthenticated: Bool { accessToken != nil }

    /// サインイン後のユーザーアクセストークン（JWT）を設定する。未設定時は anon キーのみ。
    func setAccessToken(_ token: String?) {
        self.accessToken = token
    }

    /// アクセストークン＋リフレッシュトークンをまとめて設定する。
    /// refresh_token を保持することで、アクセストークン期限切れ(401 JWT expired)時に自動更新できる。
    func setSession(accessToken: String?, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    /// トークン自動更新が起きたときの永続化フック（access, refresh）。
    /// Supabase の refresh_token はローテーションするため、新トークンを必ず保存し直す。
    func setTokenRefreshHandler(_ handler: @escaping @Sendable (String, String) -> Void) {
        self.onTokenRefresh = handler
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
        // NaN/Infinity を含むと JSONSerialization が Obj-C 例外を投げ try で捕捉できず即死するため、
        // 非有限の数値を null に正規化してから JSON 化する。
        let cleaned = rows.map { Self.sanitizeForJSON($0) as? [String: Any] ?? $0 }
        request.httpBody = try JSONSerialization.data(withJSONObject: cleaned)
        try await send(request)
    }

    /// JSON 化前に非有限の Double/Float（NaN/Infinity）を NSNull に置換する（再帰）。
    private static func sanitizeForJSON(_ value: Any) -> Any {
        switch value {
        case let d as Double: return d.isFinite ? d : NSNull()
        case let f as Float: return f.isFinite ? f : NSNull()
        case let n as NSNumber:
            let dv = n.doubleValue
            return dv.isFinite ? n : NSNull()
        case let dict as [String: Any]: return dict.mapValues { sanitizeForJSON($0) }
        case let arr as [Any]: return arr.map { sanitizeForJSON($0) }
        default: return value
        }
    }

    /// APNs デバイストークンを「現在ログイン中のユーザー」へ確実に紐付け直す（RPC `set_device_token`）。
    /// 旧実装は token だけを upsert していたため user_id が最初の登録者に固定され、
    /// 後発サインイン/アカウント切替で現在ユーザーへ付け替わらず push が不達だった（0022 で是正）。
    /// RPC は SECURITY DEFINER で同一トークンの他ユーザー行を剥がして auth.uid() に再割り当てする。
    func registerDeviceToken(_ token: String, platform: String = "ios") async throws {
        var request = restRequest(path: "rpc/set_device_token")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["p_token": token, "p_platform": platform])
        try await send(request)
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
    /// 1000 件ずつページングして尽きるまで取得する。初回同期（watermark 無し）の全件一括レスポンスに
    /// よるメモリ/パース負荷と、PostgREST 側 max-rows 設定による暗黙の打ち切りを避けるため。
    /// 並びは (updated_at, id) で全順序にし、OFFSET ページングでも取りこぼし/重複が出ないようにする。
    func select(table: String, updatedSince: Date?) async throws -> [[String: Any]] {
        let pageSize = 1000
        let maxPages = 100   // 暴走ガード（10万行。通常の同期で到達しない）
        var all: [[String: Any]] = []
        for page in 0..<maxPages {
            var query = "select=*&order=updated_at.asc,id.asc&limit=\(pageSize)&offset=\(page * pageSize)"
            if let updatedSince {
                let iso = ISO8601DateFormatter.supabase.string(from: updatedSince)
                query += "&updated_at=gt.\(iso)"
            }
            var request = restRequest(path: table, query: query)
            request.httpMethod = "GET"
            let data = try await send(request)
            let rows = ((try JSONSerialization.jsonObject(with: data)) as? [[String: Any]]) ?? []
            all.append(contentsOf: rows)
            if rows.count < pageSize { break }
        }
        return all
    }

    /// 当該テーブルの id だけを最大 `limit` 件取得する（削除照合用。本体列を取らず軽量）。
    /// 返り件数が `limit` に達したら呼び出し側で「打ち切り」とみなすこと。
    func selectIds(table: String, limit: Int) async throws -> [UUID] {
        var request = restRequest(path: table, query: "select=id&limit=\(limit)")
        request.httpMethod = "GET"
        let data = try await send(request)
        let json = (try JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        return json.compactMap { ($0["id"] as? String).flatMap { UUID(uuidString: $0) } }
    }

    /// 指定 id 群のプロフィールを更新時刻に依存せず取得する。
    /// 差分 pull（updated_at > 基準）はフォロー後追い相手の古いプロフィールを取り込めないため、
    /// フォロー中/フィード著者のプロフィールはこの id 指定取得で確実にローカルへ反映する。
    func fetchProfiles(ids: [UUID]) async throws -> [[String: Any]] {
        guard !ids.isEmpty else { return [] }
        let list = ids.map { $0.uuidString.lowercased() }.joined(separator: ",")
        var request = restRequest(path: "profiles", query: "select=*&id=in.(\(list))")
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
        let fullName: String?
        /// 匿名ユーザー（旧ビルドの signInAnonymously 由来）か。匿名認証は撤去したが、旧ビルドで
        /// 匿名セッションを持つ端末の復元時に「恒久アカウント」と誤認しないための判定に使う。
        let isAnonymous: Bool
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
        // 更新リクエスト自身が 401 でも再帰更新しない（無限ループ防止）。
        let data = try await send(request, allowRefresh: false)
        return try Self.parseAuthSession(data)
    }

    // MARK: - Email OTP（6桁コード。マジックリンクのディープリンク不要でネイティブ向き）

    /// メールにワンタイムコードを送る（未登録なら新規作成）。
    func sendEmailOTP(email: String) async throws {
        var request = authRequest(path: "otp")
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "create_user": true])
        try await send(request)
    }

    /// メールのワンタイムコードを検証してセッションを得る。
    func verifyEmailOTP(email: String, token: String) async throws -> AuthSession {
        var request = authRequest(path: "verify")
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["type": "email", "email": email, "token": token])
        let data = try await send(request)
        return try Self.parseAuthSession(data)
    }

    // MARK: - OAuth (Google) via PKCE（外部SDK不使用。caller が ASWebAuthenticationSession で開く）

    struct PKCEChallenge: Sendable { let url: URL; let codeVerifier: String }

    /// Google OAuth の authorize URL を PKCE で組む。返した codeVerifier は exchange 時に渡す。
    func googleAuthorizeURL(redirectTo: String) -> PKCEChallenge {
        let verifier = Self.randomCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let base = config.url.appendingPathComponent("auth/v1/authorize")
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: redirectTo),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
            URLQueryItem(name: "apikey", value: config.anonKey),
        ]
        return PKCEChallenge(url: comps?.url ?? base, codeVerifier: verifier)
    }

    /// authorize 後に返る code を PKCE で session に交換する。
    func exchangeCodeForSession(authCode: String, codeVerifier: String) async throws -> AuthSession {
        var request = authRequest(path: "token", query: "grant_type=pkce")
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["auth_code": authCode, "code_verifier": codeVerifier])
        let data = try await send(request)
        return try Self.parseAuthSession(data)
    }

    private static func randomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }
    private static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 表示名でユーザー（profiles）を検索する（相互フォローの相手探し）。
    struct RemoteProfile: Sendable, Identifiable {
        let id: UUID
        let displayName: String
        let avatarURL: String?
    }

    func searchProfiles(nameQuery: String, excluding selfId: UUID?, limit: Int = 20) async throws -> [RemoteProfile] {
        let trimmed = nameQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // 日本語など非 ASCII を確実に percent-encode する（.alphanumerics は Unicode 文字を
        // 「英数」とみなし生のまま残すため、日本語検索で不正リクエストになっていた）。
        // PostgREST のワイルドカード `*` は残す。
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~*")
        let pattern = "*\(trimmed)*".addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        var query = "select=id,display_name,avatar_url&display_name=ilike.\(pattern)&limit=\(limit)"
        if let selfId { query += "&id=neq.\(selfId.uuidString.lowercased())" }
        var request = restRequest(path: "profiles", query: query)
        request.httpMethod = "GET"
        let data = try await send(request)
        let rows = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return rows.compactMap { row in
            guard let idStr = row["id"] as? String, let id = UUID(uuidString: idStr) else { return nil }
            let name = (row["display_name"] as? String) ?? "ユーザー"
            return RemoteProfile(id: id, displayName: name, avatarURL: row["avatar_url"] as? String)
        }
    }

    /// アバター画像を avatars バケットへアップロードし、公開URL（バージョン無し）を返す。
    /// パス先頭フォルダ = uid で storage の RLS（本人のみ書込）を通過する。bucket は public。
    func uploadAvatar(userId: UUID, jpeg: Data) async throws -> String {
        let path = "\(userId.uuidString.lowercased())/avatar.jpg"
        let url = config.url.appendingPathComponent("storage/v1/object/avatars/\(path)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        if let accessToken { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = jpeg
        try await send(req)
        return config.url.appendingPathComponent("storage/v1/object/public/avatars/\(path)").absoluteString
    }

    /// 任意バケットへ写真をアップロード（private バケット可）。戻り値は "bucket/path"（photoURL に保存）。
    func uploadPhoto(bucket: String, path: String, jpeg: Data) async throws -> String {
        let url = config.url.appendingPathComponent("storage/v1/object/\(bucket)/\(path)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        if let accessToken { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = jpeg
        try await send(req)
        return "\(bucket)/\(path)"
    }

    /// "bucket/path" 形式の参照から写真バイト列を取得（private バケットは認証付きGET）。
    func downloadPhoto(ref: String) async throws -> Data {
        let url = config.url.appendingPathComponent("storage/v1/object/\(ref)")
        var req = URLRequest(url: url)
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        if let accessToken { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        return try await send(req)
    }

    struct PlanExercise: Codable, Sendable {
        let name: String
        let muscleGroup: String?
        let sets: Int
        let reps: Int
        let weight: Double
    }
    struct PlanItem: Sendable {
        let date: String
        let title: String
        let exercises: [PlanExercise]
    }

    /// AI 計画の応答（計画＋変更内容の説明メッセージ。チャットUIで使う）。
    struct PlanResult: Sendable {
        let items: [PlanItem]
        let message: String?
    }

    /// AI ワークアウト計画（Edge Function plan-workouts → Gemini）。
    /// 過去記録(history)・予定・ルーティン・目標日数に加え、体調シグナル(condition: 睡眠/HRV)、
    /// 対話履歴(messages)、現在計画(currentPlan)を渡し、種目＋セット＋重量/レップまで組ませる。
    /// 503(not_configured) など非2xx は send が throw する（呼び出し側で「準備中」扱い）。
    func planWorkouts(
        days: [String], routines: [String], weeklyGoal: Int,
        events: [[String: Any]], history: [[String: Any]], recovery: [[String: Any]],
        condition: [String: Any] = [:], messages: [[String: String]] = [], currentPlan: [[String: Any]] = []
    ) async throws -> PlanResult {
        let url = config.url.appendingPathComponent("functions/v1/plan-workouts")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // condition（HealthKit由来）等の非有限 Double は JSONSerialization が Obj-C 例外で
        // 落とすため、upsert と同じサニタイズを通す。
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.sanitizeForJSON([
            "days": days, "routines": routines, "weeklyGoal": weeklyGoal,
            "events": events, "history": history, "recovery": recovery,
            "condition": condition, "messages": messages, "currentPlan": currentPlan,
        ]))
        // AI 生成は REST 用の短いタイムアウト（15s/30s）では打ち切られるため、functions 用 session で送る。
        let data = try await send(request, via: functionsSession)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = (obj?["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let plan = (obj?["plan"] as? [[String: Any]]) ?? []
        let items: [PlanItem] = plan.compactMap { row in
            guard let d = row["date"] as? String, let t = row["title"] as? String else { return nil }
            let exs = (row["exercises"] as? [[String: Any]] ?? []).compactMap { e -> PlanExercise? in
                guard let name = e["name"] as? String else { return nil }
                // NaN/Infinity を含む Double を Int 変換すると Int(NaN) でトラップするため安全変換する。
                func intVal(_ any: Any?, _ def: Int) -> Int {
                    if let i = any as? Int { return i }
                    if let d = any as? Double, d.isFinite { return Int(d) }
                    return def
                }
                func dblVal(_ any: Any?, _ def: Double) -> Double {
                    if let d = any as? Double, d.isFinite { return d }
                    if let i = any as? Int { return Double(i) }
                    return def
                }
                return PlanExercise(
                    name: name,
                    muscleGroup: e["muscleGroup"] as? String,
                    sets: max(1, intVal(e["sets"], 3)),
                    reps: max(0, intVal(e["reps"], 10)),
                    weight: max(0, dblVal(e["weight"], 0))
                )
            }
            return PlanItem(date: d, title: t, exercises: exs)
        }
        return PlanResult(items: items, message: message)
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
        let base = config.url.appendingPathComponent("rest/v1/\(path)")
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = query
        // 不正な query で url が nil でも強制アンラップでは落とさず、query を捨てた base にフォールバック。
        return signed(URLRequest(url: components?.url ?? base))
    }

    private func authRequest(path: String, query: String? = nil) -> URLRequest {
        let base = config.url.appendingPathComponent("auth/v1/\(path)")
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = query
        return signed(URLRequest(url: components?.url ?? base))
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
    private func send(_ request: URLRequest, allowRefresh: Bool = true, via overrideSession: URLSession? = nil) async throws -> Data {
        do {
            return try await sendOnce(request, allowRefresh: allowRefresh, via: overrideSession)
        } catch let error where request.httpMethod == "GET" && Self.isTransient(error) {
            // 冪等な GET のみ、一過性の失敗（瞬断/タイムアウト/5xx）を短い待ちで1回だけ再試行する。
            // 並列 pull は1本落ちるとそのテーブルの当回分が歯抜けになるため、その場で拾い直す。
            try? await Task.sleep(nanoseconds: 500_000_000)
            return try await sendOnce(request, allowRefresh: allowRefresh, via: overrideSession)
        }
    }

    /// 一過性とみなすエラー（再試行対象）。認証・クライアント起因（4xx）は含めない。
    private static func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed].contains(urlError.code)
        }
        if case SupabaseError.http(let status, _) = error {
            return status == 502 || status == 503 || status == 504
        }
        return false
    }

    @discardableResult
    private func sendOnce(_ request: URLRequest, allowRefresh: Bool = true, via overrideSession: URLSession? = nil) async throws -> Data {
        let ses = overrideSession ?? session
        let (data, response) = try await ses.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }

        // 401 はアクセストークン(JWT)期限切れの可能性。refresh_token があれば一度だけ更新して再試行する。
        // これが無いと、起動から ~1h でトークンが切れて以降すべての同期/AI計画が 401 で止まる。
        if http.statusCode == 401, allowRefresh, refreshToken != nil {
            let usedAuth = request.value(forHTTPHeaderField: "Authorization")
            let currentAuth = accessToken.map { "Bearer \($0)" }
            // 自分のトークンがまだ最新なら本当に期限切れ → 更新。別リクエストが既に更新済みなら更新せず再試行。
            let refreshed = (usedAuth == currentAuth) ? await refreshAccessTokenIfPossible() : true
            if refreshed, let token = accessToken {
                var retry = request
                retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data2, response2) = try await ses.data(for: retry)
                guard let http2 = response2 as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
                guard (200..<300).contains(http2.statusCode) else {
                    throw SupabaseError.http(status: http2.statusCode, body: String(data: data2, encoding: .utf8) ?? "")
                }
                return data2
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// 進行中のトークンリフレッシュ（単一 in-flight）。並列 pull が同時に 401 を踏んでも
    /// refresh は 1 回だけ実行し、他は同じ Task に相乗りする。refresh_token はローテーション
    /// するため、多重発火は相互無効化 → セッション喪失（全同期停止）につながる。
    private var refreshTask: Task<Bool, Never>?

    /// refresh_token でアクセストークンを更新し、新トークンを保持＋永続化フックへ通知する。
    /// 更新できれば true。refresh_token も失効していれば false（呼び出し元で 401 を伝播 → 再ログインが必要）。
    private func refreshAccessTokenIfPossible() async -> Bool {
        if let running = refreshTask { return await running.value }
        guard let refresh = refreshToken else { return false }
        let task = Task { await self.performRefresh(refresh) }
        refreshTask = task
        let ok = await task.value
        refreshTask = nil
        return ok
    }

    private func performRefresh(_ refresh: String) async -> Bool {
        do {
            let s = try await refreshSession(refreshToken: refresh)
            accessToken = s.accessToken
            refreshToken = s.refreshToken
            onTokenRefresh?(s.accessToken, s.refreshToken)
            return true
        } catch {
            return false
        }
    }

    private static func parseAuthSession(_ data: Data) throws -> AuthSession {
        guard
            let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = dict["access_token"] as? String,
            let refreshToken = dict["refresh_token"] as? String
        else { throw SupabaseError.invalidResponse }
        let user = dict["user"] as? [String: Any]
        // userId が無効ならランダム UUID で握らず失敗させる（誤った id でセッション確立すると
        // 以後すべての RLS が弾かれ「同期されない」深刻な不整合になるため）。
        guard let userId = (user?["id"] as? String).flatMap(UUID.init) else {
            throw SupabaseError.invalidResponse
        }
        let email = user?["email"] as? String
        let meta = user?["user_metadata"] as? [String: Any]
        let fullName = (meta?["full_name"] as? String) ?? (meta?["name"] as? String)
        let isAnonymous = (user?["is_anonymous"] as? Bool) ?? false
        return AuthSession(accessToken: accessToken, refreshToken: refreshToken, userId: userId, email: email, fullName: fullName, isAnonymous: isAnonymous)
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
