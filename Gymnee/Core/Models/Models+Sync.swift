import Foundation
import SwiftData

/// 差分 pull の基準時刻（テーブルごとの「ここまで取り込んだ」）。
///
/// **ストアと同じ場所に住まわせるのが肝。**
/// 以前はこれを `UserDefaults` に置いていたため、ストアだけが作り直されたとき
/// （移行失敗による退避・再作成）に基準時刻だけが生き残り、
/// 「取得済みのつもりなのに手元は空」という食い違いが永久に解けなかった。
/// 差分 pull は `updated_at > 基準` しか取らないので、サーバーに記録が残っていても
/// 一切戻ってこない（実際にユーザーの記録が消えたまま戻らない事故を起こした）。
///
/// 基準をストアの中に置けば、ストアが作り直された瞬間に基準も一緒に消える。
/// 次の同期が自動的にフル取得になり、原因が何であれ手元がサーバーに追いつく。
///
/// ローカル専用（サーバーへは送らない・同期対象テーブルではない）。
@Model
final class SyncWatermark {
    /// 対象テーブル名（`LocalSyncEngine.syncedTables` の値）。
    var table: String
    /// このテーブルで取り込み済みの最大 `updated_at`。
    var lastPulledAt: Date

    init(table: String, lastPulledAt: Date) {
        self.table = table
        self.lastPulledAt = lastPulledAt
    }
}
