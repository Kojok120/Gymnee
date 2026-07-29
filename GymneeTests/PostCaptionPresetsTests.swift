import XCTest
@testable import Gymnee

/// 投稿コメントのプリセット挿入ロジックのテスト。
final class PostCaptionPresetsTests: XCTestCase {

    private var best: PostCaptionPresets.Preset {
        PostCaptionPresets.all.first { $0.label == "ベスト更新" }!
    }
    private var hard: PostCaptionPresets.Preset {
        PostCaptionPresets.all.first { $0.label == "追い込めた" }!
    }

    func testAppendToEmptyReturnsPresetTextOnly() {
        XCTAssertEqual(PostCaptionPresets.appending(best, to: ""), best.text)
    }

    func testAppendToWhitespaceOnlyReturnsPresetTextOnly() {
        XCTAssertEqual(PostCaptionPresets.appending(best, to: "   \n "), best.text)
    }

    func testAppendJoinsWithNewline() {
        XCTAssertEqual(PostCaptionPresets.appending(best, to: "今日の記録"), "今日の記録\n\(best.text)")
    }

    func testAppendIsIdempotentForSamePreset() {
        // 連打しても同じ文言が積み重ならない。
        let once = PostCaptionPresets.appending(best, to: "")
        let twice = PostCaptionPresets.appending(best, to: once)
        XCTAssertEqual(once, twice)
    }

    func testDifferentPresetsStack() {
        let first = PostCaptionPresets.appending(best, to: "")
        let second = PostCaptionPresets.appending(hard, to: first)
        XCTAssertEqual(second, "\(best.text)\n\(hard.text)")
    }

    func testPresetsAreNonEmptyAndUnique() {
        XCTAssertFalse(PostCaptionPresets.all.isEmpty)
        XCTAssertEqual(Set(PostCaptionPresets.all.map(\.label)).count, PostCaptionPresets.all.count)
        XCTAssertEqual(Set(PostCaptionPresets.all.map(\.text)).count, PostCaptionPresets.all.count)
        for p in PostCaptionPresets.all {
            XCTAssertFalse(p.text.isEmpty)
            XCTAssertFalse(p.symbol.isEmpty)
        }
    }
}
