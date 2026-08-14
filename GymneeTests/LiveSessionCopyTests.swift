import XCTest
@testable import Gymnee

/// 「いまトレーニング中」と応援の見せ方。
/// 他人の行動を実時間で見せる機能なので、**出す粒度と切れる時刻**が仕様そのもの。
final class LiveSessionCopyTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - 経過時間

    /// 秒は出さない。秒まで出すと監視されている感じが出る。
    func testShowsNoSeconds() {
        XCTAssertEqual(LiveSessionCopy.elapsed(from: start, now: start), "始めたところ")
        XCTAssertEqual(LiveSessionCopy.elapsed(from: start, now: start.addingTimeInterval(59)), "始めたところ")
    }

    func testShowsMinutes() {
        XCTAssertEqual(LiveSessionCopy.elapsed(from: start, now: start.addingTimeInterval(60)), "1分経過")
        XCTAssertEqual(LiveSessionCopy.elapsed(from: start, now: start.addingTimeInterval(45 * 60)), "45分経過")
    }

    func testShowsHours() {
        XCTAssertEqual(LiveSessionCopy.elapsed(from: start, now: start.addingTimeInterval(60 * 60)), "1時間経過")
        XCTAssertEqual(
            LiveSessionCopy.elapsed(from: start, now: start.addingTimeInterval(90 * 60)), "1時間30分経過"
        )
    }

    /// 時計のずれで未来から見ても壊れない。
    func testNegativeElapsedIsSafe() {
        XCTAssertEqual(LiveSessionCopy.elapsed(from: start, now: start.addingTimeInterval(-600)), "始めたところ")
    }

    // MARK: - 生きている時間

    /// 終了し損ねたセッションを延々と応援させない。上限はサーバと揃える。
    func testSessionExpires() {
        XCTAssertTrue(LiveSessionCopy.isLive(startedAt: start, now: start.addingTimeInterval(60 * 60)))
        XCTAssertTrue(
            LiveSessionCopy.isLive(startedAt: start, now: start.addingTimeInterval(LiveSessionCopy.maxDuration - 1))
        )
        XCTAssertFalse(
            LiveSessionCopy.isLive(startedAt: start, now: start.addingTimeInterval(LiveSessionCopy.maxDuration))
        )
    }

    /// サーバの `live_session_max_duration()` と同じ 3 時間。
    /// 片方だけ伸ばすと、アプリには出ないのに通知だけ飛ぶ（またはその逆）になる。
    func testMaxDurationMatchesServer() {
        XCTAssertEqual(LiveSessionCopy.maxDuration, 3 * 60 * 60)
    }

    // MARK: - スタンプ

    /// 応援は熱量のある 3 つに絞る（いいねは投稿向け）。
    func testCheerKinds() {
        XCTAssertEqual(LiveSessionCopy.cheerKinds, ["fire", "clap", "strong"])
    }

    /// 語彙は投稿のリアクションと揃える。別の記号を使うと同じ気持ちに 2 通り覚えることになる。
    func testEmojiMatchesReactionVocabulary() {
        XCTAssertEqual(LiveSessionCopy.emoji("fire"), "🔥")
        XCTAssertEqual(LiveSessionCopy.emoji("clap"), "👏")
        XCTAssertEqual(LiveSessionCopy.emoji("strong"), "💪")
        XCTAssertEqual(LiveSessionCopy.emoji("like"), "❤️")
        XCTAssertEqual(LiveSessionCopy.emoji("nope"), "❤️", "未知の種類でも空にしない")
    }

    func testEveryCheerKindHasLabelAndEmoji() {
        for kind in LiveSessionCopy.cheerKinds {
            XCTAssertFalse(LiveSessionCopy.emoji(kind).isEmpty, kind)
            XCTAssertFalse(LiveSessionCopy.label(kind).isEmpty, kind)
        }
    }
}
