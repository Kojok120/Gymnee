import XCTest
@testable import Gymnee

/// 同期の取りこぼしからの自動復帰。
/// 「取得済みのはずなのに手元が空」という食い違いを検出できることが要件。
final class SyncRecoveryTests: XCTestCase {

    /// サインイン済みなのに自分のデータが手元に無いなら、必ずフル取得し直す。
    /// 「一度でも pull した履歴」は復旧処理自身が消すことがあり当てにならないので条件にしない。
    func testRecoversWheneverSignedInAndEmpty() {
        XCTAssertTrue(SyncRecovery.needsFullResync(isSignedIn: true, localRowCount: 0))
    }

    /// 手元にデータがあるなら何もしない（毎起動でフル取得しない）。
    func testDoesNothingWhenDataExists() {
        XCTAssertFalse(SyncRecovery.needsFullResync(isSignedIn: true, localRowCount: 1))
    }

    /// ゲストは取りに行く先が無いので対象外。
    func testGuestIsNotAffected() {
        XCTAssertFalse(SyncRecovery.needsFullResync(isSignedIn: false, localRowCount: 0))
    }

    // MARK: - 旧実装（UserDefaults）の残骸掃除

    func testLegacyWatermarksAreDetectedAndPurged() {
        let defaults = UserDefaults(suiteName: "SyncRecoveryTests")!
        defaults.removePersistentDomain(forName: "SyncRecoveryTests")

        XCTAssertFalse(SyncRecovery.hasLegacyWatermarks(defaults: defaults))

        defaults.set(Date.now.timeIntervalSince1970, forKey: "\(SyncRecovery.legacyWatermarkPrefix)workouts")
        defaults.set(Date.now.timeIntervalSince1970, forKey: "\(SyncRecovery.legacyWatermarkPrefix)feed_items")
        defaults.set("keep", forKey: "gymnee.unrelated.setting")
        XCTAssertTrue(SyncRecovery.hasLegacyWatermarks(defaults: defaults))

        SyncRecovery.purgeLegacyWatermarks(defaults: defaults)
        XCTAssertFalse(SyncRecovery.hasLegacyWatermarks(defaults: defaults))
        // 関係ない設定は消さない。
        XCTAssertEqual(defaults.string(forKey: "gymnee.unrelated.setting"), "keep")

        defaults.removePersistentDomain(forName: "SyncRecoveryTests")
    }

    /// 旧キーの綴りは、掃除の対象を外さないために固定しておく。
    func testLegacyWatermarkPrefixIsStable() {
        XCTAssertEqual(SyncRecovery.legacyWatermarkPrefix, "gymnee.sync.lastPulled.")
    }
}
