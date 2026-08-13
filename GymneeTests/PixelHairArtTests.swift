import XCTest
@testable import Gymnee

/// 髪型とアクセサリー。頭に焼き込まれていた髪を層に分けたので、
/// 「素体と髪が 1 ドットもずれないこと」と「向きごとに描き分けること」を固定する。
final class PixelHairArtTests: XCTestCase {

    // MARK: - 寸法

    /// 素体・髪・アクセサリーはすべて頭と同じ画枠。ずれると首から上が崩れる。
    func testEveryLayerMatchesTheHeadFrame() {
        for facing in CharacterScene.Facing.allCases {
            for blinking in [true, false] {
                let base = PixelHairArt.headBase(facing: facing, blinking: blinking)
                XCTAssertEqual(base.width, PixelCharacterArt.headWidth, "\(facing) の素体幅")
                XCTAssertEqual(base.height, PixelCharacterArt.headHeight, "\(facing) の素体高")
            }
            for style in PixelHairArt.styles {
                let hair = PixelHairArt.hair(styleId: style.id, facing: facing)
                XCTAssertEqual(hair.width, PixelCharacterArt.headWidth, "\(style.id)/\(facing) の髪幅")
                XCTAssertEqual(hair.height, PixelCharacterArt.headHeight, "\(style.id)/\(facing) の髪高")
            }
            for accessory in PixelHairArt.accessories {
                guard let sprite = PixelHairArt.accessorySprite(id: accessory.id, facing: facing) else { continue }
                XCTAssertEqual(sprite.width, PixelCharacterArt.headWidth, "\(accessory.id)/\(facing) の幅")
                XCTAssertEqual(sprite.height, PixelCharacterArt.headHeight, "\(accessory.id)/\(facing) の高さ")
            }
        }
    }

    /// 素体 + 既定の髪 = 旧・焼き込み版。**既存ユーザーの見た目を変えない**ための固定。
    func testDefaultHairReproducesTheBakedHead() {
        func composite(_ base: PixelSprite, _ hair: PixelSprite) -> Set<String> {
            // 「どのドットに何を置くか」を集合で比べる（髪は素体の上に重なる）。
            var cells: [String: String] = [:]
            for run in base.runs {
                for i in 0..<run.length { cells["\(run.x + i),\(run.y)"] = String(run.ink.rawValue) }
            }
            for run in hair.runs {
                for i in 0..<run.length { cells["\(run.x + i),\(run.y)"] = String(run.ink.rawValue) }
            }
            return Set(cells.map { "\($0.key)=\($0.value)" })
        }
        func baked(_ sprite: PixelSprite) -> Set<String> {
            var cells: [String: String] = [:]
            for run in sprite.runs {
                for i in 0..<run.length { cells["\(run.x + i),\(run.y)"] = String(run.ink.rawValue) }
            }
            return Set(cells.map { "\($0.key)=\($0.value)" })
        }

        XCTAssertEqual(
            composite(PixelHairArt.headBaseFront, PixelHairArt.hair(styleId: "short", facing: .down)),
            baked(PixelCharacterArt.headFront),
            "正面が旧版と一致しない"
        )
        XCTAssertEqual(
            composite(PixelHairArt.headBaseBack, PixelHairArt.hair(styleId: "short", facing: .up)),
            baked(PixelCharacterArt.headBack),
            "背面が旧版と一致しない"
        )
        XCTAssertEqual(
            composite(PixelHairArt.headBaseSide, PixelHairArt.hair(styleId: "short", facing: .right)),
            baked(PixelCharacterArt.headSide),
            "横向きが旧版と一致しない"
        )
    }

    // MARK: - 描き分け

    func testHairStylesDifferFromEachOther() {
        let fronts = PixelHairArt.styles.map { PixelHairArt.hair(styleId: $0.id, facing: .down) }
        XCTAssertEqual(Set(fronts.map { $0.runs.count }).count > 1, true, "全部同じ形の髪型がある")
        for style in PixelHairArt.styles {
            XCTAssertNotEqual(
                PixelHairArt.hair(styleId: style.id, facing: .down),
                PixelHairArt.hair(styleId: style.id, facing: .up),
                "\(style.id) の正面と背面が同じ絵"
            )
        }
    }

    /// 未知の id は既定の髪型に落ちる（データが壊れても頭が消えない）。
    func testUnknownStyleFallsBackToDefault() {
        XCTAssertEqual(
            PixelHairArt.hair(styleId: "nope", facing: .down),
            PixelHairArt.hair(styleId: PixelHairArt.defaultStyleId, facing: .down)
        )
        XCTAssertEqual(PixelHairArt.style(id: nil).id, PixelHairArt.defaultStyleId)
    }

    // MARK: - アクセサリー

    func testNoneMeansNothingIsDrawn() {
        for facing in CharacterScene.Facing.allCases {
            XCTAssertNil(PixelHairArt.accessorySprite(id: "none", facing: facing))
            XCTAssertNil(PixelHairArt.accessorySprite(id: "unknown", facing: facing))
        }
    }

    /// 後ろからメガネは見えない。
    func testFaceAccessoriesAreHiddenFromBehind() {
        XCTAssertNil(PixelHairArt.accessorySprite(id: "glasses", facing: .up))
        XCTAssertNil(PixelHairArt.accessorySprite(id: "shades", facing: .up))
        // イヤホンは後ろからでも見える。
        XCTAssertNotNil(PixelHairArt.accessorySprite(id: "earphones", facing: .up))
    }

    // MARK: - 所持

    func testFreeItemsAreOwnedFromTheStart() {
        for style in PixelHairArt.styles where !style.isPaid {
            XCTAssertTrue(PixelHairArt.isOwned(style, purchased: []))
        }
        for accessory in PixelHairArt.accessories where !accessory.isPaid {
            XCTAssertTrue(PixelHairArt.isOwned(accessory, purchased: []))
        }
    }

    func testPaidItemsNeedPurchase() {
        guard let paid = PixelHairArt.styles.first(where: \.isPaid) else { return XCTFail("有料の髪型が無い") }
        XCTAssertFalse(PixelHairArt.isOwned(paid, purchased: []))
        XCTAssertTrue(PixelHairArt.isOwned(paid, purchased: [paid.id]))
    }

    /// 既定は無料で、初期状態でも必ず着られる。
    func testDefaultsAreFree() {
        XCTAssertTrue(PixelHairArt.isOwned(PixelHairArt.style(id: PixelHairArt.defaultStyleId), purchased: []))
        XCTAssertTrue(PixelHairArt.isOwned(PixelHairArt.accessory(id: "none"), purchased: []))
    }

    /// 髪型・アクセサリーは **CharacterLoadout に列を足さず別モデル**で持つ。
    /// 既存モデルへの列追加はスキーマのチェックサム問題を招き、
    /// 実際にユーザーのローカルデータ消失を起こした。
    func testStyleIsItsOwnModel() {
        let style = CharacterStyle(userId: UUID())
        XCTAssertEqual(style.hairStyleId, PixelHairArt.defaultStyleId)
        XCTAssertEqual(style.accessoryId, "none")
        XCTAssertTrue(style.purchased.isEmpty)
    }

    /// `purchased` は 1.4.1 以前のダミー購入の名残で、**読み取り専用のレガシー付与**。
    /// 書き込み口は塞いだ（実所持は StoreKit が正）ので、当時の値が読めることだけを保証する。
    func testLegacyGrantsAreStillReadable() {
        let style = CharacterStyle(userId: UUID(), purchasedIds: "long,ponytail")
        XCTAssertEqual(style.purchased, ["ponytail", "long"])
        XCTAssertTrue(CharacterStyle(userId: UUID(), purchasedIds: "").purchased.isEmpty)
    }

    /// 返答に JSON の断片が混ざっていたら画面に出さない（生 JSON が吹き出しに出た事故の再発防止）。
    func testRawJSONIsNeverPresentable() {
        XCTAssertFalse(CoachPersona.isPresentable("{ \"reply\": \"胸と背中の疲労度が高いから"))
        XCTAssertFalse(CoachPersona.isPresentable("[1,2]"))
        XCTAssertFalse(CoachPersona.isPresentable("   "))
        XCTAssertTrue(CoachPersona.isPresentable("今日は肩を休めよう"))
    }

    /// id は保存値なので変えると既存ユーザーの見た目が飛ぶ。
    func testIdsAreStable() {
        XCTAssertEqual(PixelHairArt.defaultStyleId, "short")
        XCTAssertEqual(Set(PixelHairArt.styles.map(\.id)), ["short", "buzz", "ponytail", "long"])
        XCTAssertEqual(Set(PixelHairArt.accessories.map(\.id)), ["none", "glasses", "shades", "earphones"])
    }
}
