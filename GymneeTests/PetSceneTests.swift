import XCTest
@testable import Gymnee

/// ペットの居場所と動き。キャラと同じく**時刻から決定的に導出**するので、
/// 同じ時刻なら何度呼んでも同じ結果になることが前提になる。
final class PetSceneTests: XCTestCase {

    private let ownerSeed: UInt64 = 0x1234_5678
    private let petSeed: UInt64 = 0x9ABC_DEF0

    private func pose(_ t: TimeInterval, away: Bool = false) -> PetScene.Pose {
        PetScene.pose(at: t, ownerSeed: ownerSeed, seed: petSeed, ownerAway: away)
    }

    /// 状態を持たない＝同じ入力なら必ず同じ出力。
    /// これが崩れるとバックグラウンド復帰でペットが飛ぶ。
    func testIsDeterministic() {
        for t in stride(from: 0.0, through: 40.0, by: 3.7) {
            XCTAssertEqual(pose(t), pose(t), "時刻 \(t) で結果が揺れた")
        }
    }

    /// 部屋の外へ出ない。キャラと同じ範囲に収める。
    func testStaysInsideTheRoom() {
        for t in stride(from: 0.0, through: 120.0, by: 0.9) {
            let p = pose(t)
            XCTAssertTrue(CharacterScene.xRange.contains(Double(p.position.x)), "x が範囲外: \(p.position.x)")
            XCTAssertTrue(CharacterScene.yRange.contains(Double(p.position.y)), "y が範囲外: \(p.position.y)")
        }
    }

    /// 負の時刻でも落ちない（`.animation` の初回フレームで負になり得る）。
    func testNegativeTimeIsClamped() {
        let p = pose(-5)
        XCTAssertTrue(CharacterScene.xRange.contains(Double(p.position.x)))
        XCTAssertTrue(CharacterScene.yRange.contains(Double(p.position.y)))
    }

    /// 飼い主のそばにいる。ずらしはあるが、離れっぱなしにはならない。
    func testStaysNearTheOwner() {
        for t in stride(from: 0.0, through: 90.0, by: 1.3) {
            let pet = pose(t).position
            // ペットは followDelay ぶん遅れた位置を目標にするので、
            // 「その時点の目標」との距離が offsetRadius を超えないことを見る。
            let target = CharacterScene.pose(at: max(0, t - PetScene.followDelay), seed: ownerSeed).position
            let dx = Double(pet.x - target.x)
            let dy = Double(pet.y - target.y)
            let distance = (dx * dx + dy * dy).squareRoot()
            XCTAssertLessThanOrEqual(distance, PetScene.followRadius + 0.0001, "時刻 \(t) で飼い主から離れすぎ")
        }
    }

    /// 飼い主が止まっていればペットも座る（足踏みして見せない）。
    func testSitsWhenTheOwnerIsNotMoving() {
        // 飼い主が動いていない時刻を探して、そこでペットが座っていることを見る。
        var found = false
        for t in stride(from: 0.0, through: 200.0, by: 0.3) {
            let now = CharacterScene.pose(at: max(0, t - PetScene.followDelay), seed: ownerSeed).position
            let before = CharacterScene.pose(at: max(0, t - PetScene.followDelay - 0.25), seed: ownerSeed).position
            let dx = Double(now.x - before.x)
            let dy = Double(now.y - before.y)
            guard (dx * dx + dy * dy).squareRoot() < PetScene.settleDistance / 2 else { continue }
            found = true
            let p = pose(t)
            XCTAssertEqual(p.behavior, .sitting, "時刻 \(t) で座っていない")
            XCTAssertEqual(p.facing, .down, "座ったらこちらを向く")
            XCTAssertEqual(p.bob, 0)
        }
        XCTAssertTrue(found, "飼い主が止まっている時刻が見つからなかった（テストの前提が壊れている）")
    }

    /// 歩いているときは向きが移動方向と一致する。
    func testFacingMatchesMovement() {
        var walked = false
        for t in stride(from: 0.0, through: 120.0, by: 0.4) {
            let p = pose(t)
            guard p.behavior == .walking else { continue }
            walked = true
            XCTAssertTrue((0..<1).contains(p.walkPhase))
        }
        XCTAssertTrue(walked, "一度も歩かなかった")
    }

    /// 遠征中は部屋の主がいないので、ドアの近くで留守番する。
    /// 待っている姿そのものが「いま遠征中」の説明になる。
    func testWaitsByTheDoorWhileTheOwnerIsAway() {
        for t in stride(from: 0.0, through: 60.0, by: 4.0) {
            let p = pose(t, away: true)
            XCTAssertEqual(p.position, PetScene.waitSpot)
            XCTAssertEqual(p.behavior, .sitting)
        }
        // ドアのそばであること。
        let dx = Double(PetScene.waitSpot.x - ExpeditionDeparture.doorSpot.x)
        let dy = Double(PetScene.waitSpot.y - ExpeditionDeparture.doorSpot.y)
        XCTAssertLessThan((dx * dx + dy * dy).squareRoot(), 0.25)
    }

    // MARK: - 撫でられたとき

    /// 撫でている間に歩き出すと、指から逃げたように見える。位置は動かさない。
    func testReactingKeepsPositionAndFacesViewer() {
        let base = pose(12)
        let reacting = PetScene.reactingPose(base: base, elapsed: 0.3)
        XCTAssertEqual(reacting?.position, base.position, "反応で立ち位置が動いた")
        XCTAssertEqual(reacting?.facing, .down)
        XCTAssertEqual(reacting?.behavior, .happy)
    }

    func testReactionEndsAfterDuration() {
        let base = pose(12)
        XCTAssertNotNil(PetScene.reactingPose(base: base, elapsed: 0))
        XCTAssertNotNil(PetScene.reactingPose(base: base, elapsed: PetScene.reactionDuration - 0.01))
        XCTAssertNil(PetScene.reactingPose(base: base, elapsed: PetScene.reactionDuration + 0.01))
        XCTAssertNil(PetScene.reactingPose(base: base, elapsed: -1))
    }

    /// 反応の長さは共通の `TapReaction` と揃える（絵が消えたあとも跳ね続けない）。
    func testReactionMatchesTheParticleWindow() {
        XCTAssertEqual(PetScene.reactionDuration, TapReaction.duration)
    }
}

/// ペットのカタログ。持っていないものを描かないことがいちばん大事。
final class PetCatalogTests: XCTestCase {

    func testResolveDropsUnownedPets() {
        XCTAssertNil(PetCatalog.resolve(selected: "shiba", owned: []), "未所持のペットは連れ歩けない")
        XCTAssertEqual(PetCatalog.resolve(selected: "shiba", owned: ["shiba"])?.id, "shiba")
    }

    /// 返金・失効で所持が消えたら自動で「連れていない」に落ちる。
    func testRefundFallsBackToNoPet() {
        XCTAssertNil(PetCatalog.resolve(selected: "tabby", owned: ["shiba"]))
    }

    func testNoneIsNeverAPet() {
        XCTAssertNil(PetCatalog.pet(id: PetCatalog.noneId))
        XCTAssertNil(PetCatalog.pet(id: nil))
        XCTAssertNil(PetCatalog.resolve(selected: PetCatalog.noneId, owned: ["shiba", "tabby"]))
    }

    func testUnknownIdIsIgnored() {
        XCTAssertNil(PetCatalog.pet(id: "dragon"))
        XCTAssertNil(PetCatalog.resolve(selected: "dragon", owned: ["dragon"]))
    }

    /// ペット id は保存値かつ product id の一部なので、変えると既存購入者が所持を失う。
    func testPetIDsAreFrozen() {
        XCTAssertEqual(PetCatalog.all.map(\.id), ["shiba", "tabby"])
        XCTAssertEqual(PetCatalog.noneId, "none")
    }

    /// すべてのペットが売り物として登録されている（買えないペットを並べない）。
    func testEveryPetHasAProduct() {
        for pet in PetCatalog.all {
            XCTAssertNotNil(StoreCatalog.entry(kind: .pet, contentID: pet.id), pet.id)
        }
        XCTAssertEqual(StoreCatalog.all.filter { $0.kind == .pet }.count, PetCatalog.all.count)
    }
}
