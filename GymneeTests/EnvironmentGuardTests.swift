import XCTest
@testable import Gymnee

/// 環境不変条件（ビルド種別×接続先ホストの整合）のテスト。
/// dev→prod データ混入の呼び水（本番ビルドが dev に繋ぐ／dev ビルドが prod に繋ぐ）を遮断する。
final class EnvironmentGuardTests: XCTestCase {

    private let prod = EnvironmentGuard.prodHost               // ibtrbymfmxrruuwuzell.supabase.co
    private let dev = "bdeaeykruwxazdoewxmg.supabase.co"
    private let appProd = "com.gymnee.app"
    private let appDev = "com.gymnee.app.dev"

    func testReleaseBuildAllowsOnlyProd() {
        XCTAssertTrue(EnvironmentGuard.allowsRemote(bundleIdentifier: appProd, host: prod))
        XCTAssertFalse(EnvironmentGuard.allowsRemote(bundleIdentifier: appProd, host: dev))
        XCTAssertFalse(EnvironmentGuard.allowsRemote(bundleIdentifier: appProd, host: "someone-else.supabase.co"))
    }

    func testDebugBuildRejectsProd() {
        // 本件の直接対策: dev ビルドが本番へ繋ぐのを禁止（デモ/検証データが prod を汚さない）。
        XCTAssertFalse(EnvironmentGuard.allowsRemote(bundleIdentifier: appDev, host: prod))
        // dev ビルドは dev や任意の非本番ホストには繋いでよい。
        XCTAssertTrue(EnvironmentGuard.allowsRemote(bundleIdentifier: appDev, host: dev))
        XCTAssertTrue(EnvironmentGuard.allowsRemote(bundleIdentifier: appDev, host: "my-local-dev.supabase.co"))
    }

    func testHostNormalization() {
        // スキーム付き・大文字・前後空白でも本番ホスト判定がぶれない。
        XCTAssertTrue(EnvironmentGuard.allowsRemote(bundleIdentifier: appProd, host: "https://\(prod)"))
        XCTAssertTrue(EnvironmentGuard.allowsRemote(bundleIdentifier: appProd, host: "  \(prod.uppercased())  "))
        // dev ビルド + スキーム付き本番ホスト → 拒否。
        XCTAssertFalse(EnvironmentGuard.allowsRemote(bundleIdentifier: appDev, host: "https://\(prod)"))
    }

    func testUnknownBundleTreatedAsRelease() {
        // .dev サフィックスが無い bundle は Release 扱い（本番のみ許可）＝安全側。
        XCTAssertTrue(EnvironmentGuard.allowsRemote(bundleIdentifier: appProd, host: prod))
        XCTAssertFalse(EnvironmentGuard.allowsRemote(bundleIdentifier: nil, host: dev))
    }
}
