import Foundation

/// フィード投稿の公開範囲の解決ルール（公開面の fail-closed 設計・docs/identity-environment-design.md）。
///
/// 原則:
/// 1. ユーザーの明示選択（PostVisibilityStore）が常に最優先。
/// 2. 既存投稿は明示選択が無ければ**現状維持**する。既定値で上書きしない
///    （明示選択は端末ローカル保存のため、別端末の再発行で既定値=public に巻き戻る事故を防ぐ）。
/// 3. 新規投稿だけが既定値（ユーザー設定のデフォルト公開範囲）を使う。
enum FeedVisibilityPolicy {
    /// - Parameters:
    ///   - explicitChoice: 投稿単位の明示選択（無ければ nil）
    ///   - existingItemVisibility: 既存 feed_item の現在値（新規投稿なら nil）
    ///   - defaultVisibility: ユーザー設定のデフォルト公開範囲
    static func resolve(
        explicitChoice: Visibility?,
        existingItemVisibility: Visibility?,
        defaultVisibility: Visibility
    ) -> Visibility {
        explicitChoice ?? existingItemVisibility ?? defaultVisibility
    }
}
