import Foundation

/// Supabase 接続設定。環境別 xcconfig（`Config/Secrets.dev.xcconfig` / `Secrets.prod.xcconfig`）が
/// ビルド設定 → Info.plist 経由で注入した値を読む。
///
/// 接続先の選択（TestFlight と App Store は同一バイナリなので、実行時にレシートで判定して切り替える）:
/// - Debug（Xcode/シミュレータ）        → dev（`SUPABASE_HOST` / `SUPABASE_KEY` = Secrets.dev）
/// - Release かつ TestFlight（sandboxReceipt）→ dev（`SUPABASE_HOST_DEV` / `SUPABASE_KEY_DEV`）
/// - Release かつ App Store（本番レシート）  → prod（`SUPABASE_HOST` / `SUPABASE_KEY` = Secrets.prod）
///
/// `*_DEV` が未設定なら main（`SUPABASE_HOST` / `SUPABASE_KEY`）にフォールバックする。
/// prod をまだ分離していない移行期（main=dev）に TestFlight のバックエンドが切れないようにするため。
/// ※ prod 分離後は `*_DEV` を必ず設定すること（未設定だと TestFlight が main=prod に落ちてしまう）。
///
/// 未設定（プレースホルダのまま／空）なら `nil`＝アプリはローカルのみで動作（オフラインファーストを維持）。
struct SupabaseConfig: Sendable {
    let url: URL
    let anonKey: String

    static func load(bundle: Bundle = .main) -> SupabaseConfig? {
        let keys = channelKeys()
        // 選んだ組（TestFlight は *_DEV）→ 無ければ main（SUPABASE_HOST/KEY）へフォールバック。
        return make(bundle, hostKey: keys.host, keyKey: keys.key)
            ?? make(bundle, hostKey: "SUPABASE_HOST", keyKey: "SUPABASE_KEY")
    }

    /// 実行時の配信チャネルに応じて読む Info.plist キー名。
    private static func channelKeys() -> (host: String, key: String) {
        #if DEBUG
        return ("SUPABASE_HOST", "SUPABASE_KEY")                 // Debug は常に dev（Secrets.dev）
        #else
        if isTestFlight { return ("SUPABASE_HOST_DEV", "SUPABASE_KEY_DEV") }  // TestFlight は dev
        return ("SUPABASE_HOST", "SUPABASE_KEY")                 // App Store は prod（Secrets.prod）
        #endif
    }

    /// TestFlight/サンドボックス配信か（本番 App Store は "receipt"、TestFlight は "sandboxReceipt"）。
    /// SubscriptionService.isTestFlight と同判定（配信チャネル判定はここでも独立に必要なため保持）。
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// 指定キーの host/key を Info.plist から読み、妥当なら SupabaseConfig を返す（未設定・プレースホルダは nil）。
    private static func make(_ bundle: Bundle, hostKey: String, keyKey: String) -> SupabaseConfig? {
        func info(_ key: String) -> String? {
            (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard
            let host = info(hostKey),
            let key = info(keyKey),
            !host.isEmpty, !key.isEmpty,
            !host.contains("YOUR_"),     // example のプレースホルダは未設定扱い
            !key.contains("YOUR_"),
            !host.contains("$("),        // ビルド設定の置換に失敗したケースを弾く
            let url = URL(string: host.hasPrefix("http") ? host : "https://\(host)")
        else {
            return nil
        }
        return SupabaseConfig(url: url, anonKey: key)
    }
}
