import XCTest
@testable import Gymnee

/// サインイン時のローカルデータ引き継ぎ（付け替え）可否判定のテスト。
/// 原則: 引き継ぎは「ローカルゲスト → 本人アカウント確定」の一方向のみ。
/// 恒久アカウントのデータを別アカウントのサインインで吸い上げない
/// （2026-07-10 の dev→prod デモデータ混入の再発防止。docs/identity-environment-design.md §4）。
final class IdentityAdoptionPolicyTests: XCTestCase {

    private let guestId = UUID()
    private let accountA = UUID()
    private let accountB = UUID()

    func testGuestToFirstSignInAdopts() {
        // ローカルゲスト（バックエンド永続化なし）→ 初回サインイン: 引き継ぐ。
        XCTAssertTrue(IdentityAdoptionPolicy.shouldAdopt(
            oldUserId: guestId, newUserId: accountA,
            persistedBackendUserId: nil
        ))
    }

    func testPermanentAccountSwitchDoesNotAdopt() {
        // 恒久アカウント A のセッションが残る端末で B にサインイン: 吸い上げ禁止（本件の再発防止の核）。
        XCTAssertFalse(IdentityAdoptionPolicy.shouldAdopt(
            oldUserId: accountA, newUserId: accountB,
            persistedBackendUserId: accountA
        ))
    }

    func testSameUserReauthDoesNotAdopt() {
        // 同一ユーザーの再認証（old == new）: 付け替え不要。
        XCTAssertFalse(IdentityAdoptionPolicy.shouldAdopt(
            oldUserId: accountA, newUserId: accountA,
            persistedBackendUserId: accountA
        ))
    }

    func testNoPreviousSessionDoesNotAdopt() {
        // 直前セッション無し（セッション復元・初回サインイン直行）: 付け替え対象が無い。
        XCTAssertFalse(IdentityAdoptionPolicy.shouldAdopt(
            oldUserId: nil, newUserId: accountA,
            persistedBackendUserId: nil
        ))
    }

    func testGuestAfterSignOutAdoptsOnlyGuestData() {
        // サインアウト（バックエンド永続化はクリア・ローカル識別はローテーション）後の
        // 新ゲスト → 別アカウント B: ゲスト期間のデータは引き継いでよい
        // （付け替え対象は old=新ゲスト uid の行だけで、旧アカウントの行は動かない）。
        XCTAssertTrue(IdentityAdoptionPolicy.shouldAdopt(
            oldUserId: guestId, newUserId: accountB,
            persistedBackendUserId: nil
        ))
    }

    func testStalePermanentPersistenceBlocksAdoptionEvenAcrossEnvironments() {
        // 別環境（dev）で確立した恒久セッションの uid が残ったまま、本番で新規アカウントに
        // サインインしたケース（Taiga 混入事故の再現形）: 吸い上げ禁止。
        XCTAssertFalse(IdentityAdoptionPolicy.shouldAdopt(
            oldUserId: accountA, newUserId: accountB,
            persistedBackendUserId: accountA
        ))
    }
}
