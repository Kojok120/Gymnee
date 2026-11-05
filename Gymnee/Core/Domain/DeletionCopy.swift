import Foundation

/// 戻せない削除の確認文（#168）。消える中身を数で書く（「本当に？」だけでは判断できないため）。
///
/// 入口（フィード・自分の投稿・記録一覧・日別・写真・下書き）で文面がばらばらにならないよう、ここに集める。
enum DeletionCopy {

    /// ワークアウトを消したときに一緒に消えるもの。
    struct WorkoutFacts: Equatable, Sendable {
        var exercises: Int
        var sets: Int
        /// 投稿している（feed_item がある）か。
        var isPublished: Bool
        /// 投稿にもらったリアクションの数。
        var reactions: Int
        var hasPhoto: Bool
    }

    static let workoutTitle = "この記録を削除しますか？"
    static let prTitle = "この自己ベストを削除しますか？"
    static let draftTitle = "記録中の内容を破棄しますか？"
    static let photoTitle = "この写真を削除しますか？"

    /// 投稿の取り下げだけをしたい人のための選択肢の名前。
    static let makePrivateLabel = "非公開にする（記録は残す）"

    static func workoutMessage(_ f: WorkoutFacts) -> String {
        var parts: [String] = []
        if f.sets > 0 {
            parts.append("\(f.exercises)種目・\(f.sets)セットの記録が消え、カレンダーと分析からも無くなります。")
        } else {
            parts.append("この記録が消え、カレンダーと分析からも無くなります。")
        }
        if f.isPublished {
            parts.append(f.reactions > 0 ? "投稿と、もらったリアクション（\(f.reactions)件）も消えます。" : "投稿も消えます。")
        }
        if f.hasPhoto { parts.append("写真も消えます。") }
        parts.append("元に戻せません。")
        if f.isPublished { parts.append("投稿を取り下げるだけなら「非公開にする」を選んでください。") }
        return parts.joined()
    }

    static func prMessage(isPublished: Bool) -> String {
        isPublished
            ? "自己ベストの記録と投稿が消えます。元に戻せません。投稿を取り下げるだけなら「非公開にする」を選んでください。"
            : "自己ベストの記録が消えます。元に戻せません。"
    }

    /// 記録中の下書き。サーバーには送っていないので、消すと復旧の手段が無い。
    static func draftMessage(sets: Int) -> String {
        sets > 0
            ? "記録中の\(sets)セットを破棄します。まだ保存していないので、元に戻せません。"
            : "記録中の内容を破棄します。"
    }

    static let photoMessage = "この端末とサーバーの両方から消え、元に戻せません。"

    // MARK: - すべてのデータの削除（#169）

    /// 設定の「すべてのデータを削除」の文面。サインインしているかで消える範囲が違うので出し分ける。
    struct AccountDeletion: Equatable, Sendable {
        let buttonLabel: String
        let title: String
        let message: String
        let confirmLabel: String
        let footer: String
    }

    static func accountDeletion(isSignedIn: Bool) -> AccountDeletion {
        if isSignedIn {
            // App Store の審査ガイドライン 5.1.1(v)（アプリ内でアカウントを削除できること）の導線も兼ねる。
            return AccountDeletion(
                buttonLabel: "アカウントを削除",
                title: "アカウントを削除しますか？",
                message: "サーバー上の記録・フレンド・投稿・連携（AI・Slack・Discord）もすべて消え、ほかの端末からも見られなくなります。サインアウトされ、元に戻せません。",
                confirmLabel: "アカウントを削除",
                footer: "アカウントを削除すると、この端末とサーバーの両方からデータが消えます。残したい記録は先に CSV で書き出してください。"
            )
        }
        return AccountDeletion(
            buttonLabel: "すべてのデータを削除",
            title: "この端末のデータを削除しますか？",
            message: "この端末の記録がすべて消えます。サインインしていないので、ほかの場所には残っていません。元に戻せません。",
            confirmLabel: "削除する",
            footer: "残したい記録は先に CSV で書き出してください。"
        )
    }
}
