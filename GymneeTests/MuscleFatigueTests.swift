import XCTest
@testable import Gymnee

/// 人体図の塗り分けに使う疲労度（負荷量 × 未回復度）のテスト。
final class MuscleFatigueTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func hoursAgo(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }

    private func status(_ muscle: MuscleGroup, in list: [MuscleFatigue.Status]) -> MuscleFatigue.Status {
        list.first { $0.muscle == muscle }!
    }

    // MARK: - 基本

    func testUntrainedMuscleHasZeroFatigue() {
        let list = MuscleFatigue.statuses(entries: [], asOf: now)
        XCTAssertEqual(list.count, RecoveryAnalyzer.trackedMuscles.count)
        for s in list {
            XCTAssertEqual(s.fatigue, 0, accuracy: 0.0001)
            XCTAssertNil(s.lastTrained)
            XCTAssertEqual(s.level, .recovered)
        }
    }

    func testJustFinishedHeavySessionIsMaxFatigue() {
        // 直後（経過0h）＋十分なセット数 → 疲労度 1.0
        let e = MuscleFatigue.SessionEntry(muscle: .chest, completedAt: now, setCount: MuscleFatigue.heavySetCount)
        let s = status(.chest, in: MuscleFatigue.statuses(entries: [e], asOf: now))
        XCTAssertEqual(s.fatigue, 1.0, accuracy: 0.0001)
        XCTAssertEqual(s.level, .fatigued)
    }

    func testFullyRecoveredIsZeroEvenAfterHeavySession() {
        // chest の推奨回復は 60h。それを超えていれば疲労は消える。
        let e = MuscleFatigue.SessionEntry(muscle: .chest, completedAt: hoursAgo(80), setCount: 20)
        let s = status(.chest, in: MuscleFatigue.statuses(entries: [e], asOf: now))
        XCTAssertEqual(s.fatigue, 0, accuracy: 0.0001)
        XCTAssertEqual(s.level, .recovered)
    }

    // MARK: - 負荷量が効くこと（RecoveryAnalyzer 単体との違い）

    func testLightSessionIsLessFatiguedThanHeavyAtSameElapsedTime() {
        let light = MuscleFatigue.SessionEntry(muscle: .arms, completedAt: hoursAgo(12), setCount: 2)
        let heavy = MuscleFatigue.SessionEntry(muscle: .chest, completedAt: hoursAgo(12), setCount: 12)
        let list = MuscleFatigue.statuses(entries: [light, heavy], asOf: now)
        XCTAssertLessThan(status(.arms, in: list).fatigue, status(.chest, in: list).fatigue)
    }

    func testIntensityFactorSaturates() {
        XCTAssertEqual(MuscleFatigue.intensityFactor(setCount: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(MuscleFatigue.intensityFactor(setCount: MuscleFatigue.heavySetCount), 1, accuracy: 0.0001)
        XCTAssertEqual(MuscleFatigue.intensityFactor(setCount: MuscleFatigue.heavySetCount * 5), 1, accuracy: 0.0001)
        XCTAssertEqual(MuscleFatigue.intensityFactor(setCount: -3), 0, accuracy: 0.0001)
    }

    // MARK: - 部位ごとの回復時間差

    func testLargeMuscleStaysFatiguedLongerThanSmall() {
        // legs=72h / arms=48h。同じ経過時間・同じセット数なら legs の方が疲労が残る。
        let legs = MuscleFatigue.SessionEntry(muscle: .legs, completedAt: hoursAgo(36), setCount: 12)
        let arms = MuscleFatigue.SessionEntry(muscle: .arms, completedAt: hoursAgo(36), setCount: 12)
        let list = MuscleFatigue.statuses(entries: [legs, arms], asOf: now)
        XCTAssertGreaterThan(status(.legs, in: list).fatigue, status(.arms, in: list).fatigue)
    }

    // MARK: - 複数セッション

    func testOnlyLatestSessionPerMuscleCounts() {
        let old = MuscleFatigue.SessionEntry(muscle: .back, completedAt: hoursAgo(70), setCount: 20)
        let recent = MuscleFatigue.SessionEntry(muscle: .back, completedAt: hoursAgo(1), setCount: 6)
        let list = MuscleFatigue.statuses(entries: [old, recent], asOf: now)
        let s = status(.back, in: list)
        XCTAssertEqual(s.lastTrained, recent.completedAt)
        XCTAssertEqual(s.lastSetCount, 6)
    }

    func testOrderOfEntriesDoesNotMatter() {
        let a = MuscleFatigue.SessionEntry(muscle: .back, completedAt: hoursAgo(70), setCount: 20)
        let b = MuscleFatigue.SessionEntry(muscle: .back, completedAt: hoursAgo(1), setCount: 6)
        let forward = MuscleFatigue.statuses(entries: [a, b], asOf: now)
        let reversed = MuscleFatigue.statuses(entries: [b, a], asOf: now)
        XCTAssertEqual(forward, reversed)
    }

    func testFutureEntriesAreIgnored() {
        // 端末の時刻ズレや手入力ミスで未来日の記録が混ざっても壊れない。
        let future = MuscleFatigue.SessionEntry(muscle: .abs, completedAt: now.addingTimeInterval(3600), setCount: 12)
        let s = status(.abs, in: MuscleFatigue.statuses(entries: [future], asOf: now))
        XCTAssertNil(s.lastTrained)
        XCTAssertEqual(s.fatigue, 0, accuracy: 0.0001)
    }

    // MARK: - 値域と表示段階

    func testFatigueAlwaysWithinUnitInterval() {
        for hours in stride(from: 0.0, through: 100.0, by: 7.0) {
            for sets in [0, 1, 5, 12, 40] {
                let e = MuscleFatigue.SessionEntry(muscle: .shoulders, completedAt: hoursAgo(hours), setCount: sets)
                let f = status(.shoulders, in: MuscleFatigue.statuses(entries: [e], asOf: now)).fatigue
                XCTAssertTrue(f.isFinite)
                XCTAssertGreaterThanOrEqual(f, 0)
                XCTAssertLessThanOrEqual(f, 1)
            }
        }
    }

    func testLevelBoundaries() {
        let e = MuscleFatigue.SessionEntry(muscle: .chest, completedAt: now, setCount: MuscleFatigue.heavySetCount)
        XCTAssertEqual(status(.chest, in: MuscleFatigue.statuses(entries: [e], asOf: now)).level, .fatigued)
        // 60h の推奨回復に対し 45h 経過（残り 0.25）× 満載 → 回復中
        let mid = MuscleFatigue.SessionEntry(muscle: .chest, completedAt: hoursAgo(45), setCount: MuscleFatigue.heavySetCount)
        XCTAssertEqual(status(.chest, in: MuscleFatigue.statuses(entries: [mid], asOf: now)).level, .recovering)
    }

    // MARK: - 次にやる候補

    func testRecommendedNextPrefersRecoveredAndLargerMuscles() {
        let entries = [
            MuscleFatigue.SessionEntry(muscle: .chest, completedAt: now, setCount: 12),   // 疲労MAX
            MuscleFatigue.SessionEntry(muscle: .arms, completedAt: hoursAgo(60), setCount: 10),  // 回復済み
        ]
        let next = MuscleFatigue.recommendedNext(from: MuscleFatigue.statuses(entries: entries, asOf: now))
        XCTAssertFalse(next.contains(.chest))
        XCTAssertTrue(next.contains(.arms))
        // 未訓練（疲労0）のうち回復時間が長い大筋群（72h: back/legs/glutes）が先頭に来る。
        XCTAssertEqual(RecoveryAnalyzer.recoveryHours(for: next.first!), 72)
    }

    func testRecommendedNextIsDeterministic() {
        // 同値が並んでも順序が揺れない（提案のちらつき防止）。
        let entries = [MuscleFatigue.SessionEntry(muscle: .chest, completedAt: now, setCount: 12)]
        let statuses = MuscleFatigue.statuses(entries: entries, asOf: now)
        let a = MuscleFatigue.recommendedNext(from: statuses)
        let b = MuscleFatigue.recommendedNext(from: statuses.reversed())
        XCTAssertEqual(a, b)
    }
}
