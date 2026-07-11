import Foundation

/// Supabase 接続設定。環境別 xcconfig（`Config/Secrets.dev.xcconfig` / `Secrets.prod.xcconfig`）が
/// ビルド設定 → Info.plist 経由で注入した値を読む。Debug ビルド→dev、Release ビルド→prod。
///
/// 未設定（プレースホルダのまま／空）なら `nil`＝アプリはローカルのみで動作（オフラインファーストを維持）。
struct SupabaseConfig: Sendable {
    let url: URL
    let anonKey: String

    static func load(bundle: Bundle = .main) -> SupabaseConfig? {
        func info(_ key: String) -> String? {
            (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard
            let host = info("SUPABASE_HOST"),
            let key = info("SUPABASE_KEY"),
            !host.isEmpty, !key.isEmpty,
            !host.contains("YOUR_"),     // example のプレースホルダは未設定扱い
            !key.contains("YOUR_"),
            !host.contains("$("),        // ビルド設定の置換に失敗したケースを弾く
            let url = URL(string: host.hasPrefix("http") ? host : "https://\(host)")
        else {
            return nil
        }
        // 環境不変条件: ビルド種別（Release/Debug）と接続先ホストがズレていたらリモートを無効化する
        // （本番ビルドが dev へ／dev ビルドが prod へ繋ぐのを構造的に遮断。docs の F2）。
        guard EnvironmentGuard.allowsRemote(bundleIdentifier: bundle.bundleIdentifier, host: host) else {
            assertionFailure("環境不整合: bundle=\(bundle.bundleIdentifier ?? "nil") host=\(host) → リモート同期を無効化")
            return nil
        }
        return SupabaseConfig(url: url, anonKey: key)
    }
}
