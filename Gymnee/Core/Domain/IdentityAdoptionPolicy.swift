import Foundation

/// サインイン確定時に「直前セッションのローカルデータを新しい userId へ引き継ぐ（付け替える）」べきかの判定。
///
/// 原則（docs/identity-environment-design.md §4）:
/// 付け替えは「ゲスト（未認証ローカル）または匿名（is_anonymous）セッション → 本人アカウント確定」の
/// 一方向・一回限りに限定する。恒久アカウント（本人性のあるバックエンドセッション）が所有していた
/// データは、別アカウントのサインインで吸い上げない。
/// これが無いと、端末に残った別アカウント/別環境のデータが新規サインインしたアカウントの
/// サーバー領域へ流れ込む（2026-07-10 の dev→prod デモデータ混入の根本原因）。
enum IdentityAdoptionPolicy {
    /// - Parameters:
    ///   - oldUserId: サインイン直前のセッション userId（セッションが無ければ nil）
    ///   - newUserId: サインイン成立後の userId
    ///   - persistedBackendUserId: 端末に永続化済みのバックエンドセッション userId（無ければ nil）
    /// - Returns: oldUserId 所有のローカルデータを newUserId へ付け替えてよいか
    static func shouldAdopt(
        oldUserId: UUID?,
        newUserId: UUID,
        persistedBackendUserId: UUID?
    ) -> Bool {
        guard let oldUserId, oldUserId != newUserId else { return false }
        // 直前セッションが恒久バックエンドアカウントなら付け替え禁止（＝アカウント切替。
        // 恒久アカウントのデータを別アカウントのサインインで吸い上げない）。
        if oldUserId == persistedBackendUserId { return false }
        // それ以外（ローカルゲスト期間）のデータは初回サインインへ正規に引き継ぐ。
        return true
    }
}
