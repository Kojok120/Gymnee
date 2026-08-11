import Foundation
import OSLog
import SwiftData

/// 同期の取りこぼしからの自動復帰。
///
/// 差分 pull の基準時刻（＝どこまで取ったか）は `UserDefaults` にあり、SwiftData のストアとは別の場所に住む。
/// そのためストアだけが作り直されると「取得済みのつもりなのに手元は空」という食い違いが起き、
/// サーバーに記録が残っていても永久に戻ってこない（実際にフィードが空のままになる事故を起こした）。
///
/// 復旧フラグに頼ると、フラグがアラート表示で消費されたあとには効かない。
/// **状態そのもの（履歴はあるのに空）を毎回見て判断する**のが確実。
enum SyncRecovery {

    private static let log = Logger(subsystem: "com.gymnee.app", category: "sync")

    /// 差分基準のキーの接頭辞。`SwiftDataSyncStore.key(_:)` と対で維持する。
    static let watermarkPrefix = "gymnee.sync.lastPulled."

    /// 一度でも pull した記録があるか。
    static func hasWatermarks(defaults: UserDefaults = .standard) -> Bool {
        defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix(watermarkPrefix) }
    }

    /// 差分基準を全部捨てる。次回の pull がフル取得になる。
    static func clearWatermarks(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(watermarkPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// フル取得し直すべきか（純粋判定）。
    ///
    /// - Parameters:
    ///   - isSignedIn: 本人性のあるアカウントでサインインしているか。ゲストはサーバーに取りに行く先が無い
    ///   - hasWatermarks: 一度でも pull したことがあるか
    ///   - localRowCount: 手元にある同期対象の行数（記録＋フィード）
    ///
    /// 「取得済みのはずなのに 1 行も無い」＝ストアが作り直された、と判断する。
    /// 新規ユーザーは `hasWatermarks` が false なので対象にならない。
    static func needsFullResync(isSignedIn: Bool, hasWatermarks: Bool, localRowCount: Int) -> Bool {
        isSignedIn && hasWatermarks && localRowCount == 0
    }

    /// 手元の同期対象の行数。記録とフィードだけ数えれば十分（どちらも空なら明らかに異常）。
    @MainActor
    static func localRowCount(userId: UUID, context: ModelContext) -> Int {
        let workouts = (try? context.fetchCount(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.userId == userId })
        )) ?? 0
        let feed = (try? context.fetchCount(FetchDescriptor<FeedItem>())) ?? 0
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
        guard needsFullResync(isSignedIn: isSignedIn, hasWatermarks: hasWatermarks(), localRowCount: rows) else { return }
        log.warning("同期履歴があるのに手元が空。フル取得し直す")
        clearWatermarks()
        await sync.syncNow(force: true)
    }
}
