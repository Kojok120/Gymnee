import XCTest
@testable import Gymnee

/// コーチの 3 段階オプションと無料枠。
/// 「決めてほしい人／ほしくない人」が要望の出発点なので、段階ごとの振る舞いを固定する。
final class CoachModeTests: XCTestCase {

    func testOffHidesCoachEntirely() {
        XCTAssertFalse(CoachMode.off.showsCoach)
        XCTAssertTrue(CoachMode.auto.showsCoach)
        XCTAssertTrue(CoachMode.suggest.showsCoach)
    }

    /// 「提案だけ」はメニューを確定しない（下書き止まり）。
    func testOnlyAutoDecidesMenu() {
        XCTAssertTrue(CoachMode.auto.decidesMenu)
        XCTAssertFalse(CoachMode.suggest.decidesMenu)
        XCTAssertFalse(CoachMode.off.decidesMenu)
    }

    func testDefaultIsSuggest() {
        XCTAssertEqual(CoachMode.default, .suggest)
    }

    func testEveryModeHasLabels() {
        for mode in CoachMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.detail.isEmpty)
        }
    }

    func testRawValuesAreStable() {
        // 保存キーの値なので、変えると既存ユーザーの設定が飛ぶ。
        XCTAssertEqual(CoachMode.auto.rawValue, "auto")
        XCTAssertEqual(CoachMode.suggest.rawValue, "suggest")
        XCTAssertEqual(CoachMode.off.rawValue, "off")
        XCTAssertEqual(CoachMode.storageKey, "gymnee.coachMode")
    }
}

/// 相談回数の上限。行き止まりにせず、翌日また触れることを保証する。
///
/// サブスクリプションは提供していないので、上限をプランで出し分けることはしない
/// （これはコスト制御であって課金の話ではない）。
final class CoachQuotaTests: XCTestCase {

    func testRemainingCountsDown() {
        XCTAssertEqual(CoachQuota.remaining(sentToday: 0), CoachQuota.dailyMessages)
        XCTAssertEqual(CoachQuota.remaining(sentToday: 3), CoachQuota.dailyMessages - 3)
    }

    func testRemainingNeverGoesNegative() {
        XCTAssertEqual(CoachQuota.remaining(sentToday: 9_999), 0)
        XCTAssertEqual(CoachQuota.remaining(sentToday: -5), CoachQuota.dailyMessages)
    }

    func testCanSendUntilLimit() {
        XCTAssertTrue(CoachQuota.canSend(sentToday: CoachQuota.dailyMessages - 1))
        XCTAssertFalse(CoachQuota.canSend(sentToday: CoachQuota.dailyMessages))
    }

    /// 上限に達しても行き止まりにしない（また明日、と伝える）。
    /// 存在しない有料プランを示唆しないことも同時に固定する（2.1(b) の再発防止）。
    func testLimitMessageIsNotADeadEndAndSellsNothing() {
        let message = CoachQuota.limitMessage
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(message.contains("明日"), message)
        for word in ["プラン", "有料", "課金", "アップグレード"] {
            XCTAssertFalse(message.contains(word), "存在しないプランを示唆している: \(message)")
        }
    }

    func testCountResetsOnANewDay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(CoachQuota.resetIfNeeded(lastSent: nil, now: now), "初回は数え直し")
        XCTAssertFalse(CoachQuota.resetIfNeeded(lastSent: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(CoachQuota.resetIfNeeded(lastSent: now.addingTimeInterval(-60 * 60 * 24 * 2), now: now))
    }
}

/// コーチに渡す要約。**渡していない情報はコーチが知り得ない**ので、何を渡すかは意図して決める。
final class CoachBriefTests: XCTestCase {

    func testPayloadCarriesTheEssentials() {
        let brief = CoachBrief(
            weeklyDone: 2, weeklyGoal: 3, streakWeeks: 4, recordedToday: false,
            daysSinceLastWorkout: 1,
            recentSessions: [.init(daysAgo: 1, title: "胸の日", totalSets: 12, volumeKg: 4200, muscles: ["胸", "腕"])],
            fatigueByMuscle: ["胸": 0.8],
            recentRecords: ["ベンチプレス 最大重量 80"]
        )
        let payload = brief.payload
        XCTAssertEqual(payload["weeklyDone"] as? Int, 2)
        XCTAssertEqual(payload["streakWeeks"] as? Int, 4)
        XCTAssertEqual(payload["recordedToday"] as? Bool, false)
        XCTAssertEqual(payload["daysSinceLastWorkout"] as? Int, 1)
        let sessions = payload["recentSessions"] as? [[String: Any]]
        XCTAssertEqual(sessions?.first?["title"] as? String, "胸の日")
        XCTAssertEqual(sessions?.first?["volumeKg"] as? Int, 4200)
        XCTAssertEqual((payload["fatigue"] as? [String: Int])?["胸"], 80)
    }

    /// 個人が特定できる情報を混ぜない（名前・メール・写真は要約に持たせていない）。
    func testPayloadHasNoIdentifyingKeys() {
        let payload = CoachBrief().payload
        for key in ["name", "displayName", "email", "userId", "photo", "avatar"] {
            XCTAssertNil(payload[key], "\(key) が要約に混ざっている")
        }
    }

    /// 非有限の値は JSON 化で落ちるので、要約の時点で外す。
    func testNonFiniteValuesAreDropped() {
        let brief = CoachBrief(
            recentSessions: [.init(daysAgo: 0, title: "x", totalSets: 1, volumeKg: .nan, muscles: [])],
            fatigueByMuscle: ["胸": .infinity],
            sleepHours: .nan,
            restingHeartRate: .infinity
        )
        let payload = brief.payload
        XCTAssertNil(payload["sleepHours"])
        XCTAssertNil(payload["restingHeartRate"])
        XCTAssertEqual((payload["recentSessions"] as? [[String: Any]])?.first?["volumeKg"] as? Int, 0)
        XCTAssertTrue((payload["fatigue"] as? [String: Int])?.isEmpty ?? false)
        // JSON 化できることまで確かめる（ここが落ちると送信そのものが失敗する）。
        XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
    }

    func testEmptyBriefIsStillValidJSON() {
        XCTAssertTrue(JSONSerialization.isValidJSONObject(CoachBrief().payload))
    }

    /// 人格の禁止事項は仕様そのものなので、消えていないことを固定する。
    func testPersonaKeepsItsGuardrails() {
        let instruction = CoachPersona.instruction
        XCTAssertTrue(instruction.contains("責めない"), "サボりを責めない指示が消えている")
        XCTAssertTrue(instruction.contains("医療"), "医療的な断定を避ける指示が消えている")
        XCTAssertTrue(instruction.contains("記録に無い事実を作らない"), "作話を禁じる指示が消えている")
        XCTAssertFalse(CoachPersona.offlineFallback.isEmpty)
        XCTAssertFalse(CoachPersona.notConfigured.isEmpty)
    }
}
