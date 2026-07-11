import Foundation

/// 環境不変条件（docs/identity-environment-design.md「F2 環境の不変条件化」）。
///
/// dev→prod データ混入（2026-07-10）の根本の呼び水は「本番ビルドが誤って DEV バックエンドに
/// 接続し、その端末のローカルデータが後で本番へ流れた」ことだった。これを構造的に塞ぐため、
/// **ビルド種別（bundle id サフィックス＝コンパイル時に焼き込まれ実行時に偽装できない）と
/// 接続先ホストの整合を起動時に強制**する。破っていたらリモート同期を無効化（＝ローカルのみで
/// 動作）し、環境をまたぐ push/pull を一切させない。
///
/// - Release（無印 bundle `com.gymnee.app`）は**本番ホストにのみ**接続してよい。
/// - Debug（`.dev` サフィックス bundle）は**本番ホストへ接続不可**（dev 検証・デモデータが prod を汚さない）。
///
/// デモ/シードデータ生成は別途 `#if DEBUG` で Release バイナリから完全に除外されているため、
/// このガード（Debug が prod に繋がらない）と合わせて「デモデータが本番に到達する経路」は二重に塞がれる。
enum EnvironmentGuard {
    /// 本番 Supabase プロジェクトの正規ホスト。Release ビルドはここにしか接続してはならない。
    /// prod プロジェクトを移行したらここも更新する（更新漏れ時はガードが働き「ローカルのみ」で
    /// 動作＝安全側に倒れる。誤って別環境へ書き込むより望ましい）。
    static let prodHost = "ibtrbymfmxrruuwuzell.supabase.co"

    /// ビルド種別（bundleIdentifier の `.dev` 有無）と接続先ホストの整合を満たすか。
    /// false ならリモート同期を無効化する（SupabaseConfig.load が nil を返す）。
    static func allowsRemote(bundleIdentifier: String?, host: String) -> Bool {
        let normalizedHost = host.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: .whitespaces)
        let connectingToProd = normalizedHost == prodHost
        // bundle id サフィックスは project.yml の BUNDLE_ID_SUFFIX（Debug=".dev" / Release=""）由来で
        // バイナリに焼き込まれる。実行時の設定値では偽装できない、信頼できるビルド種別の判定材料。
        let isDevBuild = (bundleIdentifier ?? "").hasSuffix(".dev")
        return isDevBuild ? !connectingToProd : connectingToProd
    }
}
