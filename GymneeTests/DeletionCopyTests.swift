import XCTest
@testable import Gymnee

/// #168 / #169: 戻せない削除の確認文は、消える中身を数と範囲で書く。
final class DeletionCopyTests: XCTestCase {

    func testWorkoutMessageCountsWhatDisappears() {
        let text = DeletionCopy.workoutMessage(.init(exercises: 3, sets: 9, isPublished: true, reactions: 2, hasPhoto: true))
        XCTAssertTrue(text.contains("3種目・9セット"))
        XCTAssertTrue(text.contains("リアクション（2件）"))
        XCTAssertTrue(text.contains("写真も消えます"))
        XCTAssertTrue(text.contains("元に戻せません"))
        // 投稿の取り下げだけで済む人への案内
        XCTAssertTrue(text.contains("非公開にする"))
    }

    func testUnpublishedWorkoutDoesNotMentionPost() {
        let text = DeletionCopy.workoutMessage(.init(exercises: 1, sets: 3, isPublished: false, reactions: 0, hasPhoto: false))
        XCTAssertFalse(text.contains("投稿"))
        XCTAssertFalse(text.contains("非公開"))
        XCTAssertFalse(text.contains("写真"))
    }

    func testEmptyWorkoutDoesNotSayZeroSets() {
        let text = DeletionCopy.workoutMessage(.init(exercises: 0, sets: 0, isPublished: false, reactions: 0, hasPhoto: false))
        XCTAssertFalse(text.contains("0セット"))
    }

    func testPublishedWithoutReactions() {
        let text = DeletionCopy.workoutMessage(.init(exercises: 1, sets: 1, isPublished: true, reactions: 0, hasPhoto: false))
        XCTAssertTrue(text.contains("投稿も消えます"))
        XCTAssertFalse(text.contains("件）"))
    }

    func testDraftMessageSaysItIsNotSaved() {
        XCTAssertTrue(DeletionCopy.draftMessage(sets: 4).contains("4セット"))
        XCTAssertTrue(DeletionCopy.draftMessage(sets: 4).contains("まだ保存していない"))
    }

    func testAccountDeletionForSignedInUserNamesTheWholeScope() {
        let copy = DeletionCopy.accountDeletion(isSignedIn: true)
        XCTAssertEqual(copy.buttonLabel, "アカウントを削除")
        for word in ["サーバー", "フレンド", "投稿", "ほかの端末", "サインアウト", "元に戻せません"] {
            XCTAssertTrue(copy.message.contains(word), word)
        }
        // 端末だけが消えるような書き方をしない（#169）
        XCTAssertFalse(copy.message.contains("この端末上の全記録"))
    }

    func testAccountDeletionForGuestIsDeviceOnly() {
        let copy = DeletionCopy.accountDeletion(isSignedIn: false)
        XCTAssertEqual(copy.buttonLabel, "すべてのデータを削除")
        XCTAssertTrue(copy.message.contains("この端末"))
        XCTAssertFalse(copy.message.contains("サーバー上"))
    }

    func testFootersDoNotLeakSpecJargon() {
        for signedIn in [true, false] {
            let footer = DeletionCopy.accountDeletion(isSignedIn: signedIn).footer
            XCTAssertFalse(footer.contains("APPI"))
            XCTAssertFalse(footer.contains("§"))
        }
    }
}
