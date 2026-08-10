import XCTest
@testable import Gymnee

/// コーチの来訪。**常駐させない**のが要件なので、
/// 「用事がなければ来ない」「見送った直後に戻ってこない」を固定する。
final class CoachVisitTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - 用事の判定

    func testTopicComesFromActionableLine() {
        XCTAssertEqual(CoachVisit.Topic(action: .claim), .claim)
        XCTAssertEqual(CoachVisit.Topic(action: .startWorkout), .workout)
        XCTAssertEqual(CoachVisit.Topic(action: .expedition), .expedition)
        // 雑談には用事が無い。
        XCTAssertNil(CoachVisit.Topic(action: nil))
    }

    func testNoVisitWithoutErrand() {
        XCTAssertFalse(CoachVisit.shouldVisit(topic: nil, lastDismissed: nil, now: now))
    }

    func testVisitsWhenErrandAppearsFirstTime() {
        XCTAssertTrue(CoachVisit.shouldVisit(topic: .workout, lastDismissed: nil, now: now))
    }

    // MARK: - クールダウン

    /// 見送った直後は同じ用事で戻ってこない。
    /// 「今日まだ記録していない」は 1 日じゅう成り立つので、これが無いと結局は常駐になる。
    func testDoesNotReturnImmediatelyForSameTopic() {
        let dismissed = (topic: CoachVisit.Topic.workout, at: now)
        XCTAssertFalse(CoachVisit.shouldVisit(topic: .workout, lastDismissed: dismissed, now: now))
        XCTAssertFalse(
            CoachVisit.shouldVisit(
                topic: .workout, lastDismissed: dismissed,
                now: now.addingTimeInterval(CoachVisit.cooldown - 60)
            )
        )
    }

    func testReturnsAfterCooldown() {
        let dismissed = (topic: CoachVisit.Topic.workout, at: now)
        XCTAssertTrue(
            CoachVisit.shouldVisit(
                topic: .workout, lastDismissed: dismissed,
                now: now.addingTimeInterval(CoachVisit.cooldown)
            )
        )
    }

    /// 用事が変わったらクールダウン中でもすぐ来る。
    /// 遠征の帰還を 3 時間待たせる理由が無い。
    func testDifferentTopicIgnoresCooldown() {
        let dismissed = (topic: CoachVisit.Topic.workout, at: now)
        XCTAssertTrue(
            CoachVisit.shouldVisit(topic: .claim, lastDismissed: dismissed, now: now.addingTimeInterval(60))
        )
    }

    // MARK: - 出入り

    func testAwayDrawsNothing() {
        XCTAssertNil(CoachVisit.pose(phase: .away, elapsed: 0, spot: spot))
    }

    /// 入ってくるときは画面外から立ち位置へ、歩きながら右を向いて移動する。
    func testArrivingWalksInFromOffstage() {
        let start = CoachVisit.pose(phase: .arriving, elapsed: 0, spot: spot)
        XCTAssertEqual(Double(start?.position.x ?? 0), CoachVisit.offstageX, accuracy: 0.001)
        XCTAssertEqual(start?.facing, .right)
        XCTAssertEqual(start?.behavior, .walking)

        let end = CoachVisit.pose(phase: .arriving, elapsed: CoachVisit.transitionDuration, spot: spot)
        XCTAssertEqual(Double(end?.position.x ?? 0), Double(spot.x), accuracy: 0.001)
    }

    /// 出ていくときは逆向きに、立ち位置から画面外へ。
    func testLeavingWalksOut() {
        let start = CoachVisit.pose(phase: .leaving, elapsed: 0, spot: spot)
        XCTAssertEqual(Double(start?.position.x ?? 0), Double(spot.x), accuracy: 0.001)
        XCTAssertEqual(start?.facing, .left)

        let end = CoachVisit.pose(phase: .leaving, elapsed: CoachVisit.transitionDuration, spot: spot)
        XCTAssertEqual(Double(end?.position.x ?? 0), CoachVisit.offstageX, accuracy: 0.001)
    }

    /// 移動中に位置が飛ばない（ワープして見えない）。
    func testTransitionIsMonotonic() {
        var previous = CoachVisit.offstageX
        for step in stride(from: 0.0, through: CoachVisit.transitionDuration, by: 0.05) {
            let x = Double(CoachVisit.pose(phase: .arriving, elapsed: step, spot: spot)?.position.x ?? 0)
            XCTAssertGreaterThanOrEqual(x, previous - 0.0001, "elapsed=\(step) で後ずさりした")
            previous = x
        }
    }

    func testPresentStandsStillAndBreathes() {
        let pose = CoachVisit.pose(phase: .present, elapsed: 5, spot: spot)
        XCTAssertEqual(pose?.position, spot)
        XCTAssertEqual(pose?.facing, .down, "立っているときはこちらを向く")
        XCTAssertEqual(pose?.behavior, .emoting(.rest))
    }

    func testTransitionFinishes() {
        XCTAssertFalse(CoachVisit.isTransitionFinished(elapsed: CoachVisit.transitionDuration - 0.1))
        XCTAssertTrue(CoachVisit.isTransitionFinished(elapsed: CoachVisit.transitionDuration))
    }

    private let spot = CGPoint(x: 0.23, y: 0.14)
}

/// 相談の中身。答えは必ず現在の記録から導き、行動につながるものには操作を添える。
final class CoachConsultationTests: XCTestCase {

    func testAlwaysOffersSomethingToAsk() {
        let topics = CoachConsultation.topics(for: CharacterChatter.Context())
        XCTAssertFalse(topics.isEmpty)
        for topic in topics {
            XCTAssertFalse(topic.question.isEmpty, "\(topic.id) の質問が空")
            XCTAssertFalse(topic.answer.isEmpty, "\(topic.id) の答えが空")
        }
    }

    func testTopicIdsAreUnique() {
        let ids = CoachConsultation.topics(for: CharacterChatter.Context()).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    /// 行動が要る答えには必ずボタンの文言が付く（押せない案内で終わらせない）。
    func testActionableAnswersCarryAButtonTitle() {
        let contexts = [
            CharacterChatter.Context(recordedToday: false, weeklyDone: 0, weeklyGoal: 3),
            CharacterChatter.Context(recordedToday: true, energy: 200, cheapestCourseCost: 20, expedition: .idle),
            CharacterChatter.Context(recordedToday: true, expedition: .awaitingClaim),
        ]
        for context in contexts {
            for topic in CoachConsultation.topics(for: context) where topic.action != nil {
                XCTAssertNotNil(topic.actionTitle, "\(topic.id) に操作の文言が無い")
            }
        }
    }

    func testTodayPromptsWorkoutWhenNotRecorded() {
        let topics = CoachConsultation.topics(
            for: CharacterChatter.Context(recordedToday: false, weeklyDone: 2, weeklyGoal: 3)
        )
        let today = topics.first { $0.id == "today" }
        XCTAssertEqual(today?.action, .startWorkout)
        XCTAssertTrue(today?.answer.contains("あと1回") == true, today?.answer ?? "")
    }

    /// 今日すでに記録している人を追い立てない。
    func testTodayDoesNotPushWhenAlreadyRecorded() {
        let topics = CoachConsultation.topics(for: CharacterChatter.Context(recordedToday: true))
        XCTAssertNil(topics.first { $0.id == "today" }?.action)
    }

    func testEnergyOffersExpeditionWhenAffordable() {
        let topics = CoachConsultation.topics(
            for: CharacterChatter.Context(recordedToday: true, energy: 80, cheapestCourseCost: 20, expedition: .idle)
        )
        XCTAssertEqual(topics.first { $0.id == "energy" }?.action, .expedition)
    }

    func testEnergyTellsHowMuchIsMissing() {
        let topics = CoachConsultation.topics(
            for: CharacterChatter.Context(recordedToday: true, energy: 5, cheapestCourseCost: 20, expedition: .idle)
        )
        let answer = topics.first { $0.id == "energy" }?.answer ?? ""
        XCTAssertTrue(answer.contains("あと15"), answer)
    }

    func testEnergyOffersClaimWhenExpeditionReturned() {
        let topics = CoachConsultation.topics(
            for: CharacterChatter.Context(recordedToday: true, expedition: .awaitingClaim)
        )
        XCTAssertEqual(topics.first { $0.id == "energy" }?.action, .claim)
    }

    /// 長く空いている人を責めない（週次ストリークの思想に合わせる）。
    func testConditionIsGentleAfterALongBreak() {
        let topics = CoachConsultation.topics(
            for: CharacterChatter.Context(streakWeeks: 0, daysSinceLastWorkout: 21)
        )
        let answer = topics.first { $0.id == "condition" }?.answer ?? ""
        XCTAssertTrue(answer.contains("責めはしない"), answer)
    }

    func testEvolutionReportsWhatIsMissing() {
        let topics = CoachConsultation.topics(
            for: CharacterChatter.Context(nextStageUnmet: ["Lv.5まであと2", "自己ベストあと1"])
        )
        let answer = topics.first { $0.id == "evolution" }?.answer ?? ""
        XCTAssertTrue(answer.contains("Lv.5まであと2"), answer)
        XCTAssertTrue(answer.contains("自己ベストあと1"), answer)
    }
}
