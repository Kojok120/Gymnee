import Foundation

/// 外部連携（#171）の URL まわりの純粋ロジック。
enum ConnectEndpoint {
    /// 本番の外部連携サーバー（Cloudflare Worker `gymnee-connect`）。
    static let production = URL(string: "https://api.gymnee.app")!

    /// アプリから呼ぶ外部連携サーバーの URL。
    /// ローカル Supabase に繋いでいる Debug ビルドは、同じ Mac の `wrangler dev --env local`（:8787）へ向ける。
    /// Release が本番以外へ繋がないことは `EnvironmentGuard` が Supabase 側で保証している。
    static func baseURL(supabaseURL: URL) -> URL {
        guard let host = supabaseURL.host?.lowercased() else { return production }
        let isLocal = host == "127.0.0.1" || host == "localhost" || host.hasPrefix("192.168.") || host.hasPrefix("10.")
        guard isLocal, let local = URL(string: "http://\(host):8787") else { return production }
        return local
    }
}

/// AI（MCP クライアント）の接続を承認するリンク。
/// ブラウザの承認画面が出す `https://gymnee.app/connect/approve?p=<id>`（ユニバーサルリンク）と、
/// 開かなかったとき用の `gymnee://connect/approve?p=<id>` の 2 つを受ける。
enum ConnectLink {
    static func pairingId(from url: URL) -> UUID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let isUniversal = components.scheme == "https"
            && components.host == "gymnee.app"
            && components.path.hasPrefix("/connect/approve")
        let isCustom = components.scheme == "gymnee"
            && components.host == "connect"
            && components.path.hasPrefix("/approve")
        guard isUniversal || isCustom else { return nil }
        return components.queryItems?.first(where: { $0.name == "p" })?.value.flatMap(UUID.init(uuidString:))
    }
}
