import XCTest
@testable import Gymnee

final class RoomIntroTests: XCTestCase {
    func testFirstCompletionShowsCelebrationThenOnboardingThenNotification() {
        // 新規ユーザーの典型: 初回完了 → 初めて育成タブ。3つとも順番に出る（#120）。
        XCTAssertEqual(RoomIntro.steps(hasCelebration: true, needsOnboarding: true),
                       [.celebration, .onboarding, .notificationPrompt])
    }

    func testNotificationPromptOnlyAfterCelebration() {
        XCTAssertEqual(RoomIntro.steps(hasCelebration: false, needsOnboarding: true), [.onboarding])
        XCTAssertEqual(RoomIntro.steps(hasCelebration: true, needsOnboarding: false), [.celebration, .notificationPrompt])
        XCTAssertEqual(RoomIntro.steps(hasCelebration: false, needsOnboarding: false), [])
    }

    func testLateCelebrationQueuesBehindOnboardingAndKeepsNotificationLast() {
        // 遊び方を出している最中に、遅れて祝いの控えが届くケース（@Query の反映が後になる）。
        let queue = RoomIntro.enqueue([.celebration, .notificationPrompt], into: [])
        XCTAssertEqual(queue, [.celebration, .notificationPrompt])
        let withOnboarding = RoomIntro.enqueue([.onboarding], into: [.celebration, .notificationPrompt])
        XCTAssertEqual(withOnboarding, [.celebration, .onboarding, .notificationPrompt])
    }

    func testEnqueueDoesNotDuplicateSteps() {
        let queue = RoomIntro.enqueue([.celebration, .notificationPrompt], into: [.celebration, .notificationPrompt])
        XCTAssertEqual(queue, [.celebration, .notificationPrompt])
    }
}
