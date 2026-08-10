import XCTest
@testable import Gymnee

/// 部屋に落ちているグッズ。
/// ねらいは「アプリを開く理由を毎日つくること」なので、**記録がゼロでも落ちる**ことが要件。
/// そのうえで、強さ（EXP）はレアグッズだけに乗せて実質トレーニングに紐づけたままにする。
final class RoomPickupTests: XCTestCase {

    private let seed: UInt64 = 0xFEED_1234
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - 落下率

    /// 記録がゼロでも落ちなくならない（落とさない、という罰を与えない）。
    func testBaselineDropsHappenWithoutAnyTraining() {
        let multiplier = RoomPickup.multiplier(lastWeekCount: 0, weeklyGoal: 3)
        XCTAssertEqual(multiplier, 1, accuracy: 0.001)

        var slotsWithDrop = 0
        for slot in 0..<200 where RoomPickup.drop(slot: slot, seed: seed, multiplier: multiplier) != nil {
            slotsWithDrop += 1
        }
        XCTAssertGreaterThan(slotsWithDrop, 60, "記録ゼロでほとんど落ちていない（開く理由が作れない）")
    }

    /// 前の週に通った人ほど落ちやすくなる。
    func testTrainingLastWeekRaisesTheDropRate() {
        XCTAssertGreaterThan(
            RoomPickup.multiplier(lastWeekCount: 3, weeklyGoal: 3),
            RoomPickup.multiplier(lastWeekCount: 0, weeklyGoal: 3)
        )
        // 目標ちょうどで 1.2 倍。
        XCTAssertEqual(RoomPickup.multiplier(lastWeekCount: 3, weeklyGoal: 3), 1.2, accuracy: 0.001)

        func dropCount(_ multiplier: Double) -> Int {
            (0..<300).filter { RoomPickup.drop(slot: $0, seed: seed, multiplier: multiplier) != nil }.count
        }
        XCTAssertGreaterThan(dropCount(1.5), dropCount(1.0))
    }

    func testMultiplierIsBoundedAndSafe() {
        XCTAssertEqual(RoomPickup.multiplier(lastWeekCount: 999, weeklyGoal: 3), RoomPickup.maxMultiplier, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(RoomPickup.multiplier(lastWeekCount: -5, weeklyGoal: 3), 1)
        // 目標 0（設定が壊れている）でも落ちなくならない。
        XCTAssertEqual(RoomPickup.multiplier(lastWeekCount: 5, weeklyGoal: 0), 1, accuracy: 0.001)
    }

    // MARK: - 強さとの関係

    /// **EXP をくれるのはレアだけ**。ここが崩れると、通わずにレベルが上がる経路ができる。
    func testOnlyRareItemsGiveExperience() {
        for item in RoomPickup.items {
            if item.rarity == .rare {
                XCTAssertGreaterThan(item.experience, 0, "\(item.id) がレアなのに EXP 0")
            } else {
                XCTAssertEqual(item.experience, 0, "\(item.id) がレアでないのに EXP をくれる")
            }
            XCTAssertGreaterThan(item.energy, 0, "\(item.id) の元気が 0")
        }
    }

    /// レアの出現率も倍率で上がる（＝EXP は実質トレーニングに紐づく）。
    func testRareRateAlsoScalesWithTraining() {
        func rareCount(_ multiplier: Double) -> Int {
            (0..<2000).compactMap { RoomPickup.drop(slot: $0, seed: seed, multiplier: multiplier) }
                .filter { $0.item.rarity == .rare }.count
        }
        XCTAssertGreaterThan(rareCount(RoomPickup.maxMultiplier), rareCount(1.0))
    }

    /// 拾って得られる EXP は 1 セッションより十分小さい（現実が主役のままであること）。
    func testPickupExperienceStaysSmallVersusASession() {
        let session = CharacterProgress.SessionInput(completedAt: now, completedSets: 12, volumeKg: 4000)
        let sessionExp = CharacterProgress.experience(for: session)
        let bestPickup = RoomPickup.items.map(\.experience).max() ?? 0
        XCTAssertLessThan(bestPickup, sessionExp / 3, "1 個拾うだけで 1 回分に迫っている")
    }

    // MARK: - 湧きの決定性

    func testDropsAreDeterministic() {
        let a = RoomPickup.drops(now: now, seed: seed, collected: [])
        let b = RoomPickup.drops(now: now, seed: seed, collected: [])
        XCTAssertEqual(a, b)
    }

    func testDifferentUsersSeeDifferentDrops() {
        let a = RoomPickup.drops(now: now, seed: 1, collected: [])
        let b = RoomPickup.drops(now: now, seed: 2, collected: [])
        XCTAssertNotEqual(a.map(\.storageId), b.map(\.storageId))
    }

    /// 拾ったものは復活しない。
    func testCollectedDropsDoNotComeBack() {
        let first = RoomPickup.drops(now: now, seed: seed, collected: [])
        guard let target = first.first else { return XCTFail("床に何も落ちていない") }
        let after = RoomPickup.drops(now: now, seed: seed, collected: [target.storageId])
        XCTAssertFalse(after.contains { $0.storageId == target.storageId })
    }

    /// 散らかりすぎない（キャラが見えなくなる）。
    func testFloorIsCapped() {
        for step in 0..<20 {
            let date = now.addingTimeInterval(Double(step) * RoomPickup.slotDuration)
            XCTAssertLessThanOrEqual(
                RoomPickup.drops(now: date, seed: seed, collected: [], multiplier: RoomPickup.maxMultiplier).count,
                RoomPickup.maxOnFloor
            )
        }
    }

    /// 古いものは消える（何日も放置した分がまとめて残らない）。
    func testOldDropsExpire() {
        let drops = RoomPickup.drops(now: now, seed: seed, collected: [])
        let oldestAllowed = RoomPickup.slotIndex(for: now.addingTimeInterval(-RoomPickup.lifetime))
        for drop in drops {
            XCTAssertGreaterThanOrEqual(drop.slot, oldestAllowed, "寿命を超えたグッズが残っている")
        }
    }

    /// 置かれる場所は床の内側（端で見切れない）。
    func testDropsStayInsideTheFloor() {
        for slot in 0..<400 {
            guard let drop = RoomPickup.drop(slot: slot, seed: seed, multiplier: 1.3) else { continue }
            XCTAssertTrue((0.1...0.9).contains(Double(drop.position.x)), "x=\(drop.position.x)")
            XCTAssertTrue((0.15...0.9).contains(Double(drop.position.y)), "y=\(drop.position.y)")
        }
    }

    // MARK: - 合計

    func testTotalsAddUp() {
        let ids = ["coffee", "coffee", "creatine"]
        let coffee = RoomPickup.item(id: "coffee")!
        let creatine = RoomPickup.item(id: "creatine")!
        XCTAssertEqual(RoomPickup.totalEnergy(collectedItemIds: ids), coffee.energy * 2 + creatine.energy)
        XCTAssertEqual(RoomPickup.totalExperience(collectedItemIds: ids), creatine.experience)
    }

    func testUnknownItemsAreIgnored() {
        XCTAssertEqual(RoomPickup.totalEnergy(collectedItemIds: ["nope"]), 0)
        XCTAssertEqual(RoomPickup.totalExperience(collectedItemIds: ["nope"]), 0)
    }

    // MARK: - 既存の計算との合流

    func testPickupEnergyAddsToTheExpeditionFuel() {
        let sessions = [CharacterProgress.SessionInput(completedAt: now, completedSets: 10, volumeKg: 3000)]
        let base = Expedition.availableEnergy(sessions: sessions, spent: 0)
        XCTAssertEqual(Expedition.availableEnergy(sessions: sessions, spent: 0, bonus: 25), base + 25)
        // 使い切っている状態でもマイナスにならない。
        XCTAssertEqual(Expedition.availableEnergy(sessions: [], spent: 999, bonus: 10), 0)
    }

    func testPickupExperienceAddsToTheLevelSource() {
        let sessions = [CharacterProgress.SessionInput(completedAt: now, completedSets: 10, volumeKg: 3000)]
        let base = CharacterProgress.totalExperience(sessions: sessions)
        XCTAssertEqual(CharacterProgress.totalExperience(sessions: sessions, pickupBonus: 60), base + 60)
        XCTAssertEqual(CharacterProgress.totalExperience(sessions: sessions, pickupBonus: -10), base)
    }

    // MARK: - 絵

    func testEveryItemHasArt() {
        for item in RoomPickup.items {
            let sprite = PixelItemArt.pickup(id: item.id)
            XCTAssertEqual(sprite.width, PixelItemArt.pickupSide, "\(item.id) の幅")
            XCTAssertEqual(sprite.height, PixelItemArt.pickupSide, "\(item.id) の高さ")
            XCTAssertFalse(sprite.runs.isEmpty, "\(item.id) に描かれるドットが無い")
        }
    }
}
