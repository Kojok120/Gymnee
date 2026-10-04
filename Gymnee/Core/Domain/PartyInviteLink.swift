import Foundation

/// 週ボスのパーティ招待リンク（issue #128）。
///
/// 形式: `https://gymnee.app/party/?p=<パーティid>`（Universal Link）と `gymnee://party?p=<パーティid>`
/// （招待ページの「Gymnee で開く」ボタン用。同じドメイン内のリンクでは Universal Link が発火しないため）。
/// 開くと参加の確認を経て `join_party` を呼ぶ。参加の可否（満員など）はサーバーが判定する。
enum PartyInviteLink {
    private static let queryName = "p"

    /// リンクを開いた時点で未サインイン・初期設定前でも、後で参加を確認できるよう持ち越すキー。
    static let pendingDefaultsKey = "gymnee.pendingPartyId"

    static func url(for partyId: UUID) -> URL {
        URL(string: "https://\(InviteLink.host)/party/?\(queryName)=\(partyId.uuidString.lowercased())")!
    }

    static func partyId(from url: URL) -> UUID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme {
        case "https":
            guard components.host == InviteLink.host else { return nil }
            let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
            guard path == "/party" else { return nil }
        case InviteLink.appScheme:
            guard components.host == "party", components.path.isEmpty || components.path == "/" else { return nil }
        default:
            return nil
        }
        guard let value = components.queryItems?.first(where: { $0.name == queryName })?.value else { return nil }
        return UUID(uuidString: value)
    }

    static let shareMessage = "Gymneeで一緒に週ボスを倒そう！トレーニング1回が1撃になります。"
}
