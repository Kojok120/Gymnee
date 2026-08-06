import XCTest
@testable import Gymnee

/// GymneeSchema.backupStoreFiles（開けないストアの退避）のテスト。
/// 本番の復旧パスは「削除ではなく移動」が生命線なので、移動後に元の場所から消えていること・
/// 退避先に同内容で存在することを検証する。
final class StoreBackupTests: XCTestCase {
    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreBackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    private func makeStore(suffixes: [String]) throws -> URL {
        let base = workDir.appendingPathComponent("default.store")
        for s in suffixes {
            try Data("data\(s)".utf8).write(to: URL(fileURLWithPath: base.path + s))
        }
        return base
    }

    func testMovesAllStoreFilesIntoTimestampedDirectory() throws {
        let base = try makeStore(suffixes: ["", "-wal", "-shm"])
        let stamp = Date(timeIntervalSince1970: 1_754_000_000)

        let dest = GymneeSchema.backupStoreFiles(at: base, now: stamp)

        let dir = try XCTUnwrap(dest)
        // 退避先はストアと同じ親の StoreBackups/<UTC日時>。
        XCTAssertEqual(dir.deletingLastPathComponent().lastPathComponent, "StoreBackups")
        XCTAssertEqual(dir.lastPathComponent, "20250731-221320")
        for s in ["", "-wal", "-shm"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: base.path + s), "元の場所に残っている: \(s)")
            let moved = dir.appendingPathComponent("default.store" + s)
            XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "data\(s)", "内容が保全されていない: \(s)")
        }
    }

    func testMovesOnlyExistingFiles() throws {
        // -shm が無い（チェックポイント済み等）状態でも、あるものだけ移動して成功する。
        let base = try makeStore(suffixes: ["", "-wal"])

        let dest = GymneeSchema.backupStoreFiles(at: base)

        let dir = try XCTUnwrap(dest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("default.store").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("default.store-wal").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("default.store-shm").path))
    }

    func testReturnsNilWhenNothingToMove() throws {
        let base = workDir.appendingPathComponent("missing.store")
        XCTAssertNil(GymneeSchema.backupStoreFiles(at: base))
        // 空の退避ディレクトリも作らない。
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDir.appendingPathComponent("StoreBackups").path))
    }
}
