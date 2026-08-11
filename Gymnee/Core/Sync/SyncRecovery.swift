import Foundation
import OSLog
import SwiftData

/// 同期の取りこぼしからの自動復帰（`SyncWatermark` をストアに置いたことの上乗せの安全網）。
///
/// 差分 pull は `updated_at > 基準` しか取らないので、基準と手元のデータが食い違うと
/// サーバーに記録が残っていても永久に戻ってこない。基準をストアの中に移したことで
/// 「ストアが作り直された」原因は塞いだが、取り込みの部分失敗など他の食い違いは残り得る。
/// **状態そのもの（サインイン済みなのに自分のデータが無い）を毎起動で見て**取り直す。
///
/// 復旧フラグに頼ると、フラグがアラート表示で消費されたあとには効かない（実際に効かなかった）。
enum SyncRecovery {

    private static let log = Logger(subsystem: "com.gymnee.app", category: "sync")

    /// 旧実装で差分基準を置いていた `UserDefaults` キーの接頭辞。
    /// 現在の基準は `SyncWatermark`（ストア内）で、これは残骸の掃除にだけ使う。
    static let legacyWatermarkPrefix = "gymnee.sync.lastPulled."

    /// 旧実装の基準時刻が残っているか。
    static func hasLegacyWatermarks(defaults: UserDefaults = .standard) -> Bool {
        defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix(legacyWatermarkPrefix) }
    }

    /// 旧実装の基準時刻を掃除する。
    static func purgeLegacyWatermarks(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(legacyWatermarkPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// フル取得し直すべきか（純粋判定）。
    ///
    /// - Parameters:
    ///   - isSignedIn: 本人性のあるアカウントでサインインしているか。ゲストはサーバーに取りに行く先が無い
    ///   - localRowCount: 手元にある **自分の** 同期対象の行数（記録＋自分の投稿）
    ///
    /// 条件は **「サインイン済みなのに自分のデータが手元に無い」だけ**にする。
    /// 以前は「一度でも pull した履歴がある」も条件にしていたが、履歴の有無は
    /// 復旧処理そのものが消してしまうことがあり、当てにならなかった（実際にこれで復帰できなかった）。
    ///
    /// 新規ユーザーでも 1 回だけフル取得が走るが、サーバーに何も無いので実害は無く、
    /// データが入れば以後は発火しない。**確実に空から抜け出せること**を優先する。
    static func needsFullResync(isSignedIn: Bool, localRowCount: Int) -> Bool {
        isSignedIn && localRowCount == 0
    }

    /// 手元にある **自分の** 行数。自分の記録と自分の投稿だけを数える。
    ///
    /// **他人の行を数に入れてはいけない。** フォロー相手の投稿が 1 件でも降りてくると
    /// 「手元は空ではない」と誤判定し、自分のデータが戻らないまま復旧が発火しなくなる
    /// （実際にフォロー相手の投稿だけが表示され、本人の記録が戻らない事故を起こした）。
    @MainActor
    static func localRowCount(userId: UUID, context: ModelContext) -> Int {
        let workouts = (try? context.fetchCount(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.userId == userId })
        )) ?? 0
        let feed = (try? context.fetchCount(
            FetchDescriptor<FeedItem>(predicate: #Predicate { $0.userId == userId })
        )) ?? 0
        return workouts + feed
    }

    /// 必要ならフル取得し直す。起動のたびに呼んでよい（データが戻れば以後は発火しない）。
    @MainActor
    static func recoverIfNeeded(
        userId: UUID?,
        isSignedIn: Bool,
        context: ModelContext,
        sync: LocalSyncEngine
    ) async {
        guard let userId else { return }
        let rows = localRowCount(userId: userId, context: context)
        guard needsFullResync(isSignedIn: isSignedIn, localRowCount: rows) else { return }
        log.warning("サインイン済みだが自分のデータが手元に無い。フル取得し直す")
        sync.resetPullWatermarks()
        await sync.syncNow(force: true)
    }
}
