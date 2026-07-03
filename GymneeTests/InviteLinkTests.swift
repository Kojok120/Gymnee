import XCTest
@testable import Gymnee

/// フレンド招待ディープリンクの生成・解釈（§6.11）のテスト。
final class InviteLinkTests: XCTestCase {

    private let userId = UUID(uuidString: "0B944329-9BB2-4C90-8AC3-2E149A379AB5")!

    func testURLRoundTrip() {
        let url = InviteLink.url(for: userId)
        XCTAssertEqual(InviteLink.userId(from: url), userId)
    }

    func testURLFormat() {
        let url = InviteLink.url(for: userId)
        XCTAssertEqual(url.absoluteString, "https://gymnee.app/invite/?u=0b944329-9bb2-4c90-8ac3-2e149a379ab5")
    }

    func testParseAcceptsPathWithoutTrailingSlash() {
        let url = URL(string: "https://gymnee.app/invite?u=\(userId.uuidString)")!
        XCTAssertEqual(InviteLink.userId(from: url), userId)
    }

    func testParseAcceptsUppercaseUUID() {
        let url = URL(string: "https://gymnee.app/invite/?u=\(userId.uuidString.uppercased())")!
        XCTAssertEqual(InviteLink.userId(from: url), userId)
    }

    func testParseRejectsWrongHost() {
        let url = URL(string: "https://example.com/invite/?u=\(userId.uuidString)")!
        XCTAssertNil(InviteLink.userId(from: url))
    }

    func testParseRejectsWrongPath() {
        XCTAssertNil(InviteLink.userId(from: URL(string: "https://gymnee.app/?u=\(userId.uuidString)")!))
        XCTAssertNil(InviteLink.userId(from: URL(string: "https://gymnee.app/invite/extra?u=\(userId.uuidString)")!))
    }

    func testParseRejectsMissingOrMalformedUser() {
        XCTAssertNil(InviteLink.userId(from: URL(string: "https://gymnee.app/invite/")!))
        XCTAssertNil(InviteLink.userId(from: URL(string: "https://gymnee.app/invite/?u=not-a-uuid")!))
    }

    func testParseRejectsNonHTTPSScheme() {
        let url = URL(string: "http://gymnee.app/invite/?u=\(userId.uuidString)")!
        XCTAssertNil(InviteLink.userId(from: url))
    }

    func testParseRejectsOAuthCallbackScheme() {
        // Google サインインのコールバック（reversed client id スキーム）を誤検知しない。
        let url = URL(string: "com.googleusercontent.apps.123:/oauth2redirect?code=abc")!
        XCTAssertNil(InviteLink.userId(from: url))
    }
}
