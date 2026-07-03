import Foundation

/// フレンド招待ディープリンク（Universal Link）の生成・解釈（§6.11）。
///
/// 形式: `https://gymnee.app/invite/?u=<招待者のユーザーid>`
/// - 生成: AddFriendView の「友達を招待」ShareLink
/// - 解釈: GymneeApp.onOpenURL → 保留保存 → ソーシャルタブで招待者プロフィールを開く
/// - アプリ未所持で開いた場合は gymnee.app（GitHub Pages）の /invite/ ガイドページが表示される。
///   AASA は `docs/.well-known/apple-app-site-association` で配信する。
enum InviteLink {
    /// Universal Link のホスト。entitlements の `applinks:` と AASA の配信元に一致させる。
    static let host = "gymnee.app"
    private static let userQueryName = "u"

    /// リンクを開いた時点で未サインインでも、サインイン・初期設定の完了後に
    /// 招待者プロフィールへ誘導できるよう、未消費の招待者 id を持ち越す UserDefaults キー。
    static let pendingDefaultsKey = "gymnee.pendingInviteUserId"

    /// 自分のユーザー id を埋め込んだ招待リンクを生成する。
    static func url(for userId: UUID) -> URL {
        URL(string: "https://\(host)/invite/?\(userQueryName)=\(userId.uuidString.lowercased())")!
    }

    /// 開かれた URL から招待者のユーザー id を取り出す。招待リンク以外（OAuth コールバック等）は nil。
    static func userId(from url: URL) -> UUID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host == host
        else { return nil }
        // 末尾スラッシュの有無は同一視する（/invite と /invite/ の両方が届き得る）。
        let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        guard path == "/invite",
              let value = components.queryItems?.first(where: { $0.name == userQueryName })?.value
        else { return nil }
        return UUID(uuidString: value)
    }
}
