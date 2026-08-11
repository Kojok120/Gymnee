import XCTest
@testable import Gymnee

/// 同期の取りこぼしからの自動復帰。
/// 「取得済みのはずなのに手元が空」という食い違いを検出できることが要件。
final class SyncRecoveryTests: XCTestCase {

    /// ストアだけ作り直された状態（履歴あり・手元は空・サインイン済み）で復帰する。
    func testRecoversWhenSyncedBeforeButLocalIsEmpty() {
        XCTAssertTrue(
            SyncRecovery.needsFullResync(isSignedIn: true, hasWatermarks: true, localRowCount: 0)
        )
    }

    /// 新規ユーザーは対象外。まだ一度も pull していないので履歴が無い。
    func testNewUserIsNotAffected() {
        XCTAssertFalse(
            SyncRecovery.needsFullResync(isSignedIn: true, hasWatermarks: false, localRowCount: 0)
        )
    }

    /// 手元にデータがあるなら何もしない（毎起動でフル取得しない）。
    func testDoesNothingWhenDataExists() {
        XCTAssertFalse(
            SyncRecovery.needsFullResync(isSignedIn: true, hasWatermarks: true, localRowCount: 1)
        )
    }

    /// ゲストは取りに行く先が無いので対象外。
    func testGuestIsNotAffected() {
        XCTAssertFalse(
            SyncRecovery.needsFullResync(isSignedIn: false, hasWatermarks: true, localRowCount: 0)
        )
    }

    // MARK: - 差分基準の破棄

    func testWatermarksAreDetectedAndCleared() {
        let defaults = UserDefaults(suiteName: "SyncRecoveryTests")!
        defaults.removePersistentDomain(forName: "SyncRecoveryTests")

        XCTAssertFalse(SyncRecovery.hasWatermarks(defaults: defaults))

        defaults.set(Date.now.timeIntervalSince1970, forKey: "\(SyncRecovery.watermarkPrefix)workouts")
        defaults.set(Date.now.timeIntervalSince1970, forKey: "\(SyncRecovery.watermarkPrefix)feed_items")
        defaults.set("keep", forKey: "gymnee.unrelated.setting")
        XCTAssertTrue(SyncRecovery.hasWatermarks(defaults: defaults))

        SyncRecovery.clearWatermarks(defaults: defaults)
        XCTAssertFalse(SyncRecovery.hasWatermarks(defaults: defaults))
        // 関係ない設定は消さない。
        XCTAssertEqual(defaults.string(forKey: "gymnee.unrelated.setting"), "keep")

        defaults.removePersistentDomain(forName: "SyncRecoveryTests")
    }

    /// キーの綴りは同期ストア側と対で維持する必要がある。
    func testWatermarkPrefixMatchesTheStore() {
        XCTAssertEqual(SyncRecovery.watermarkPrefix, "gymnee.sync.lastPulled.")
    }
}
