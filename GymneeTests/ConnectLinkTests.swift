import XCTest
@testable import Gymnee

/// #171: AI の接続の承認リンクと、外部連携サーバーの URL。
final class ConnectLinkTests: XCTestCase {
    private let id = UUID(uuidString: "6F0F4C1E-6B3D-4B5E-9F62-3A3C1D0E7B21")!

    func testUniversalLink() {
        let url = URL(string: "https://gymnee.app/connect/approve?p=6f0f4c1e-6b3d-4b5e-9f62-3a3c1d0e7b21")!
        XCTAssertEqual(ConnectLink.pairingId(from: url), id)
    }

    func testCustomSchemeLink() {
        let url = URL(string: "gymnee://connect/approve?p=6f0f4c1e-6b3d-4b5e-9f62-3a3c1d0e7b21")!
        XCTAssertEqual(ConnectLink.pairingId(from: url), id)
    }

    func testRejectsOtherLinks() {
        // 招待・パーティのリンク、別ドメイン、id の無いリンクは承認として扱わない。
        XCTAssertNil(ConnectLink.pairingId(from: URL(string: "https://gymnee.app/invite?u=6f0f4c1e-6b3d-4b5e-9f62-3a3c1d0e7b21")!))
        XCTAssertNil(ConnectLink.pairingId(from: URL(string: "https://evil.example/connect/approve?p=6f0f4c1e-6b3d-4b5e-9f62-3a3c1d0e7b21")!))
        XCTAssertNil(ConnectLink.pairingId(from: URL(string: "https://gymnee.app/connect/approve")!))
        XCTAssertNil(ConnectLink.pairingId(from: URL(string: "https://gymnee.app/connect/approve?p=not-a-uuid")!))
        XCTAssertNil(ConnectLink.pairingId(from: URL(string: "gymnee://auth-callback?code=x")!))
    }

    func testEndpointFollowsSupabaseHost() {
        XCTAssertEqual(ConnectEndpoint.baseURL(supabaseURL: URL(string: "https://ibtrbymfmxrruuwuzell.supabase.co")!).absoluteString, "https://api.gymnee.app")
        XCTAssertEqual(ConnectEndpoint.baseURL(supabaseURL: URL(string: "http://127.0.0.1:54421")!).absoluteString, "http://127.0.0.1:8787")
    }
}
