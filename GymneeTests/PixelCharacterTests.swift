import XCTest
@testable import Gymnee

/// ドット絵の整合性。行の長さが 1 文字でもずれると絵が崩れるので、全スプライトを機械的に検証する。
final class PixelSpriteTests: XCTestCase {

    /// 検証対象のスプライト（名前つき）。新しい絵を足したらここにも足す。
    private var allSprites: [(String, PixelSprite)] {
        var list: [(String, PixelSprite)] = [
            ("head", PixelCharacterArt.head),
            ("headBlink", PixelCharacterArt.headBlink),
            ("dumbbell", PixelCharacterArt.dumbbell),
            ("backpack", PixelCharacterArt.backpack),
            ("plant", PixelCharacterArt.plant),
            ("dumbbellRack", PixelCharacterArt.dumbbellRack),
            ("bench", PixelCharacterArt.bench),
            ("barbell", PixelCharacterArt.barbell),
            ("chest", PixelCharacterArt.chest),
        ]
        for girth in CharacterBuild.Girth.allCases {
            list.append(("body-\(girth)", PixelCharacterArt.body(girth)))
        }
        for limb in CharacterBuild.Limb.allCases {
            list.append(("arm-\(limb)", PixelCharacterArt.arm(limb)))
            list.append(("leg-\(limb)", PixelCharacterArt.leg(limb)))
        }
        for rarity in Expedition.Rarity.allCases {
            list.append(("headGear-\(rarity)", PixelCharacterArt.headGear(rarity)))
            list.append(("handGear-\(rarity)", PixelCharacterArt.handGear(rarity)))
        }
        return list
    }

    func testEverySpriteHasContent() {
        for (name, sprite) in allSprites {
            XCTAssertGreaterThan(sprite.width, 0, "\(name) の幅が 0")
            XCTAssertGreaterThan(sprite.height, 0, "\(name) の高さが 0")
            XCTAssertFalse(sprite.runs.isEmpty, "\(name) に描かれるドットが 1 つも無い")
        }
    }

    /// 走査区間がスプライトの枠からはみ出していないこと（行の長さ不揃いを検出する）。
    func testRunsStayInsideBounds() {
        for (name, sprite) in allSprites {
            for run in sprite.runs {
                XCTAssertGreaterThanOrEqual(run.x, 0, "\(name) の区間が左にはみ出した")
                XCTAssertLessThanOrEqual(run.x + run.length, sprite.width, "\(name) の区間が右にはみ出した")
                XCTAssertGreaterThanOrEqual(run.y, 0, "\(name) の区間が上にはみ出した")
                XCTAssertLessThan(run.y, sprite.height, "\(name) の区間が下にはみ出した")
            }
        }
    }

    /// パーツの寸法宣言と実物が一致していること。ここがずれると合成位置が全部ずれる。
    func testDeclaredSizesMatchSprites() {
        XCTAssertEqual(PixelCharacterArt.head.width, PixelCharacterArt.headWidth)
        XCTAssertEqual(PixelCharacterArt.head.height, PixelCharacterArt.headHeight)
        XCTAssertEqual(PixelCharacterArt.headBlink.width, PixelCharacterArt.headWidth)
        XCTAssertEqual(PixelCharacterArt.headBlink.height, PixelCharacterArt.headHeight)

        for girth in CharacterBuild.Girth.allCases {
            XCTAssertEqual(PixelCharacterArt.body(girth).width, PixelCharacterArt.bodyWidth(girth), "\(girth) の胴幅")
            XCTAssertEqual(PixelCharacterArt.body(girth).height, PixelCharacterArt.bodyHeight, "\(girth) の胴高")
        }
        for limb in CharacterBuild.Limb.allCases {
            XCTAssertEqual(PixelCharacterArt.arm(limb).width, PixelCharacterArt.armWidth(limb), "\(limb) の腕幅")
            XCTAssertEqual(PixelCharacterArt.arm(limb).height, PixelCharacterArt.armHeight, "\(limb) の腕高")
            XCTAssertEqual(PixelCharacterArt.leg(limb).width, PixelCharacterArt.legWidth(limb), "\(limb) の脚幅")
            XCTAssertEqual(PixelCharacterArt.leg(limb).height, PixelCharacterArt.legHeight, "\(limb) の脚高")
        }
    }

    /// 頭の装備は頭と同じ幅（ずれると頭からはみ出す）。
    func testHeadGearMatchesHeadWidth() {
        for rarity in Expedition.Rarity.allCases {
            XCTAssertEqual(
                PixelCharacterArt.headGear(rarity).width, PixelCharacterArt.headWidth,
                "\(rarity) の頭装備が頭幅と違う"
            )
        }
    }

    /// 合成したキャラが画枠（24 × 24）に収まること。
    func testCompositionFitsCanvas() {
        for girth in CharacterBuild.Girth.allCases {
            for limb in CharacterBuild.Limb.allCases {
                let bodyW = PixelCharacterArt.bodyWidth(girth)
                let armW = PixelCharacterArt.armWidth(limb)
                let bodyX = PixelCharacterArt.canvasWidth / 2 - bodyW / 2
                // 腕は内側の輪郭を 1 ドット重ねて置く。
                let leftEdge = bodyX - armW + 1
                let rightEdge = bodyX + bodyW - 1 + armW
                XCTAssertGreaterThanOrEqual(leftEdge, 0, "\(girth)/\(limb) で左腕が枠外")
                XCTAssertLessThanOrEqual(rightEdge, PixelCharacterArt.canvasWidth, "\(girth)/\(limb) で右腕が枠外")
            }
        }
        XCTAssertEqual(PixelCharacterArt.headHeight + PixelCharacterArt.bodyHeight - 1 + PixelCharacterArt.legHeight,
                       PixelCharacterArt.canvasHeight,
                       "頭・胴・脚の合計が画枠の高さと合わない")
    }

    func testUnknownCharactersAreTransparent() {
        let sprite = PixelSprite(["?z?"])
        XCTAssertTrue(sprite.runs.isEmpty, "未知の文字が描画対象になっている")
    }

    func testRowsAreRectangularHelper() {
        XCTAssertTrue(PixelSprite.rowsAreRectangular(["ab", "cd"]))
        XCTAssertFalse(PixelSprite.rowsAreRectangular(["ab", "c"]))
    }
}

/// 体格の段階分けと、姿勢 → ドットのずらし量。
final class PixelCharacterLayoutTests: XCTestCase {

    // MARK: - 体格

    func testBuildStepsUpWithTraining() {
        let beginner = CharacterAppearance(shoulder: 0.35, arm: 0.30, leg: 0.30, torso: 0.35, aura: 0)
        let veteran = CharacterAppearance(shoulder: 1.0, arm: 1.0, leg: 1.0, torso: 1.0, aura: 1)
        XCTAssertEqual(CharacterBuild.make(from: beginner), CharacterBuild(girth: .slim, arm: .thin, leg: .thin))
        XCTAssertEqual(CharacterBuild.make(from: veteran), CharacterBuild(girth: .wide, arm: .thick, leg: .thick))
    }

    /// 部位ごとに独立して太る（脚だけ鍛えたら脚だけ太くなる）。
    func testBuildReflectsIndividualAxes() {
        let legDay = CharacterAppearance(shoulder: 0.35, arm: 0.30, leg: 0.90, torso: 0.35, aura: 0)
        let build = CharacterBuild.make(from: legDay)
        XCTAssertEqual(build.leg, .thick)
        XCTAssertEqual(build.arm, .thin)
        XCTAssertEqual(build.girth, .slim)
    }

    func testBuildHandlesNonFiniteValues() {
        let broken = CharacterAppearance(shoulder: .nan, arm: .infinity, leg: .nan, torso: .nan, aura: .nan)
        // 落ちずに何らかの体格を返せばよい（画面が壊れないことが目的）。
        _ = CharacterBuild.make(from: broken)
    }

    // MARK: - コマ

    func testWalkFrameIndexCyclesThroughAllFrames() {
        let indices = stride(from: 0.0, to: 1.0, by: 0.05).map { PixelCharacterLayout.walkFrameIndex(phase: $0) }
        XCTAssertEqual(Set(indices), Set(0..<PixelCharacterLayout.walkFrameCount))
    }

    func testWalkFrameIndexStaysInRange() {
        for phase in [-3.0, -0.1, 0, 0.999, 1.0, 2.5, Double.nan] {
            let index = PixelCharacterLayout.walkFrameIndex(phase: phase)
            XCTAssertTrue((0..<PixelCharacterLayout.walkFrameCount).contains(index), "phase=\(phase)")
        }
    }

    /// 歩行中は必ずどちらか一方の足だけが上がる（両足が同時に浮くと跳ねて見える）。
    func testWalkLiftsOneLegAtATime() {
        for step in 0..<PixelCharacterLayout.walkFrameCount {
            let phase = (Double(step) + 0.5) / Double(PixelCharacterLayout.walkFrameCount)
            let pose = pose(behavior: .walking, walkPhase: phase)
            let frame = PixelCharacterLayout.frame(for: pose)
            XCTAssertFalse(
                frame.leftLegLift > 0 && frame.rightLegLift > 0,
                "コマ \(step) で両足が浮いている"
            )
        }
    }

    func testCurlHoldsDumbbell() {
        let frame = PixelCharacterLayout.frame(for: pose(behavior: .emoting(.curl), emotePhase: 0.5))
        XCTAssertTrue(frame.holdsDumbbell)
    }

    func testCheerRaisesArms() {
        let frame = PixelCharacterLayout.frame(for: pose(behavior: .emoting(.cheer), emotePhase: 0.25))
        XCTAssertTrue(frame.armsRaised)
        XCTAssertLessThan(frame.lift, 0, "跳んでいるのに浮いていない")
    }

    func testBlinkFlagFollowsPose() {
        XCTAssertTrue(PixelCharacterLayout.frame(for: pose(behavior: .emoting(.rest), blink: 0.9)).blinking)
        XCTAssertFalse(PixelCharacterLayout.frame(for: pose(behavior: .emoting(.rest), blink: 0.1)).blinking)
    }

    /// どの仕草・どの位相でも、ずらし量が常識的な範囲を超えないこと（キャラが画面外へ飛ばない）。
    func testOffsetsStayReasonable() {
        for emote in CharacterScene.Emote.allCases {
            for step in 0...20 {
                let frame = PixelCharacterLayout.frame(
                    for: pose(behavior: .emoting(emote), emotePhase: Double(step) / 20)
                )
                XCTAssertTrue((-6...6).contains(frame.lift), "\(emote) の lift=\(frame.lift)")
                XCTAssertTrue((0...4).contains(frame.crouch), "\(emote) の crouch=\(frame.crouch)")
                XCTAssertTrue((-6...6).contains(frame.leftArmY), "\(emote) の leftArmY")
                XCTAssertTrue((-6...6).contains(frame.rightArmY), "\(emote) の rightArmY")
            }
        }
    }

    // MARK: - 補助

    private func pose(
        behavior: CharacterScene.Behavior,
        walkPhase: Double = 0,
        emotePhase: Double = 0,
        blink: Double = 0
    ) -> CharacterScene.Pose {
        CharacterScene.Pose(
            position: CGPoint(x: 0.5, y: 0.5),
            facingRight: true,
            behavior: behavior,
            walkPhase: walkPhase,
            emotePhase: emotePhase,
            breathPhase: 0,
            blink: blink
        )
    }
}
