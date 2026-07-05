import UIKit

/// Instagram ストーリーズへの直接共有（§6.6 拡張）。
/// Meta 公式の URL スキーム連携（`instagram-stories://share`）を使い、背景画像を渡して
/// ストーリーズ作成画面を直接開く。
///
/// 前提:
/// - Meta for Developers でアプリ登録した App ID を `META_APP_ID`（xcconfig → Info.plist の
///   MetaAppID）に設定する（未設定なら導線を出さない）
/// - Info.plist の LSApplicationQueriesSchemes に instagram-stories（project.yml で設定済み）
/// - Instagram 未インストール時も導線を出さない（通常の共有シートで代替できる）
@MainActor
enum InstagramSharing {
    private static var metaAppID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "MetaAppID") as? String,
              !id.isEmpty, !id.hasPrefix("$(") else { return nil }  // xcconfig 未定義の素通し値を除外
        return id
    }

    /// ストーリーズ直接共有が使えるか（Meta App ID 設定済み ＋ Instagram インストール済み）。
    static var isAvailable: Bool {
        guard metaAppID != nil, let url = URL(string: "instagram-stories://share") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// 背景画像（9:16 推奨）をペーストボード経由で渡し、Instagram のストーリーズ作成画面を開く。
    @discardableResult
    static func shareToStories(background: UIImage) -> Bool {
        guard let appID = metaAppID,
              let url = URL(string: "instagram-stories://share?source_application=\(appID)"),
              UIApplication.shared.canOpenURL(url),
              let png = background.pngData() else { return false }
        // Meta の仕様どおり、共有データは期限付きでペーストボードに置く（5分で自動失効）。
        UIPasteboard.general.setItems(
            [["com.instagram.sharedSticker.backgroundImage": png]],
            options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
        )
        UIApplication.shared.open(url)
        return true
    }
}
