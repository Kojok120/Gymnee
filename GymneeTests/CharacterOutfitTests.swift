import XCTest
@testable import Gymnee

/// 見た目まわり（体格・装備・スキン）のテスト。
/// 「装備で強さは変わらない」「持っていない物は着られない」が壊れていないかを見る。
final class CharacterOutfitTests: XCTestCase {

    // MARK: - 体格

    func testAppearanceStartsAboveZero() {
        let a = CharacterAppearance.make(stats: [:], stage: .rookie)
        XCTAssertGreaterThan(a.shoulder, 0, "記録ゼロでも棒人間にはしない")
        XCTAssertGreaterThan(a.arm, 0)
        XCTAssertEqual(a.aura, 0, accuracy: 0.0001)
    }

    func testAppearanceReflectsStats() {
        let weak = CharacterAppearance.make(stats: [.push: 0, .arms: 0, .legs: 0], stage: .rookie)
        let strong = CharacterAppearance.make(stats: [.push: 99, .arms: 99, .legs: 99], stage: .rookie)
        XCTAssertGreaterThan(strong.shoulder, weak.shoulder)
        XCTAssertGreaterThan(strong.arm, weak.arm)
        XCTAssertGreaterThan(strong.leg, weak.leg)
    }

    func testAppearanceIsClampedAndSafe() {
        let a = CharacterAppearance.make(stats: [.push: 9_999, .arms: -50], stage: .legend)
        XCTAssertLessThanOrEqual(a.shoulder, 1.0)
        XCTAssertGreaterThanOrEqual(a.arm, 0)
        XCTAssertEqual(a.aura, 1, accuracy: 0.0001, "最終段階でオーラは最大")
    }

    func testAuraGrowsWithStage() {
        let rookie = CharacterAppearance.make(stats: [:], stage: .rookie)
        let veteran = CharacterAppearance.make(stats: [:], stage: .veteran)
        XCTAssertGreaterThan(veteran.aura, rookie.aura)
    }

    // MARK: - 装備

    func testResolveKeepsOnlyOwnedItems() {
        let crown = Expedition.item(id: "crown")!
        let resolved = CharacterOutfit.resolve(loadout: [.head: "crown"], owned: [])
        XCTAssertTrue(resolved.isEmpty, "持っていない装備は着られない")

        let owned = CharacterOutfit.resolve(loadout: [.head: "crown"], owned: ["crown"])
        XCTAssertEqual(owned[.head], crown)
    }

    func testResolveRejectsWrongSlot() {
        // 頭スロットに手の装備を保存してしまっていても弾く。
        let resolved = CharacterOutfit.resolve(loadout: [.head: "power-grip"], owned: ["power-grip"])
        XCTAssertNil(resolved[.head])
    }

    func testResolveIgnoresUnknownItemId() {
        let resolved = CharacterOutfit.resolve(loadout: [.head: "no-such-item"], owned: ["no-such-item"])
        XCTAssertTrue(resolved.isEmpty)
    }

    func testCandidatesAreOwnedAndSortedByRarity() {
        let owned: Set<String> = ["sweat-band", "crown", "cap"]
        let candidates = CharacterOutfit.candidates(for: .head, owned: owned)
        XCTAssertEqual(candidates.map(\.id), ["crown", "cap", "sweat-band"])
    }

    func testAutoEquipFillsEmptySlotAndUpgrades() {
        let crown = Expedition.item(id: "crown")!
        let band = Expedition.item(id: "sweat-band")!
        XCTAssertTrue(CharacterOutfit.shouldAutoEquip(band, current: nil), "空きスロットには着せる")
        XCTAssertTrue(CharacterOutfit.shouldAutoEquip(crown, current: band), "より良いものは着せ替える")
        XCTAssertFalse(CharacterOutfit.shouldAutoEquip(band, current: crown), "格下では上書きしない")
    }

    func testEveryItemHasASlotAndEverySlotHasItems() {
        for slot in Expedition.Slot.allCases {
            XCTAssertFalse(Expedition.items(in: slot).isEmpty, "\(slot.rawValue) に装備が1つも無い")
        }
        XCTAssertEqual(Expedition.items.count, Expedition.Slot.allCases.reduce(0) { $0 + Expedition.items(in: $1).count })
    }

    // MARK: - スキン

    func testFreeSkinIsAlwaysOwnedAndPaidNeedsPurchase() {
        let free = SkinCatalog.all.first { !$0.isPaid }!
        let paid = SkinCatalog.all.first { $0.isPaid }!
        XCTAssertTrue(SkinCatalog.isOwned(free, purchased: []))
        XCTAssertFalse(SkinCatalog.isOwned(paid, purchased: []))
        XCTAssertTrue(SkinCatalog.isOwned(paid, purchased: [paid.id]))
    }

    func testUnknownSkinFallsBackToDefault() {
        XCTAssertEqual(SkinCatalog.skin(id: "nope").id, SkinCatalog.defaultSkinId)
        XCTAssertEqual(SkinCatalog.skin(id: nil).id, SkinCatalog.defaultSkinId)
    }
}
