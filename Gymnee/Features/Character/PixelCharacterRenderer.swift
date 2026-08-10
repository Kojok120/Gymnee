import SwiftUI

/// ドット絵キャラの合成と描画。
///
/// パーツ（頭・胴・腕・脚）を `PixelCharacterLayout.Frame` のずらし量どおりに重ねる。
/// **座標はすべて整数ドット**で計算し、最後にドットの一辺（pt）を掛けて画面座標にする。
/// 途中で小数を挟むとドットの境目がにじんで、ドット絵に見えなくなる。
enum PixelCharacterRenderer {

    /// 誰を描くか。骨格は共通で、頭と小物だけ差し替える。
    enum Role: Equatable {
        /// プレイヤー自身と、部屋に居合わせた仲間。
        case trainee
        /// AI コーチ（#79）。帽子とクリップボードで描き分ける。
        case coach
    }

    /// 描くのに要る材料。
    struct Look: Equatable {
        var build: CharacterBuild
        var skin: CharacterSkin
        var equipped: [Expedition.Slot: Expedition.Item]
        var stage: CharacterProgress.Stage
        /// 遠征中はリュックを背負う。
        var carriesPack: Bool
        /// 頭上に出す名前（仲間キャラ用。自分は nil）。
        var nameTag: String?
        var role: Role = .trainee
        /// 髪型（`PixelHairArt.styles`）。
        var hairStyleId: String = PixelHairArt.defaultStyleId
        /// アクセサリー（`PixelHairArt.accessories`）。"none" は着けていない。
        var accessoryId: String = "none"
    }

    /// コーチの配色。プレイヤーのスキンとは独立させる（着せ替えの対象ではない）。
    static let coachSkin = CharacterSkin(
        id: "coach", name: "コーチ",
        bodyHex: 0xD9A87F, accentHex: 0x2B4B7A,
        isPaid: false, priceLabel: ""
    )

    /// コーチの体格。プレイヤーの記録では変わらない。
    static let coachBuild = CharacterBuild(girth: .normal, arm: .thick, leg: .thick)

    // MARK: - 画枠の基準位置（ドット）

    private enum Anchor {
        /// 頭の左上。
        static let headX = 5
        static let headY = 0
        /// 胴の上端。
        static let bodyY = 12
        /// 腕の上端。
        static let armY = 13
        /// 脚の上端（胴の下端に合わせる）。
        static let legY = bodyY + PixelCharacterArt.bodyHeight
        /// 画枠の横中心。
        static let centerX = 12
    }

    // MARK: - 描画

    /// キャラ 1 体を描く。`feet` は接地点（画面座標）、`dot` は 1 ドットの一辺（pt）。
    static func draw(
        in context: inout GraphicsContext,
        look: Look,
        frame: PixelCharacterLayout.Frame,
        facing: CharacterScene.Facing,
        feet: CGPoint,
        dot: CGFloat
    ) {
        guard dot > 0 else { return }
        var palette = PixelPalette.make(skin: look.skin)
        let mirrored = facing.isMirrored
        let sideways = facing.isSideways

        // 画枠の左上（＝足元から左へ半分、上へ画枠の高さぶん）。ドット境界に吸着させる。
        let originX = (feet.x - CGFloat(PixelCharacterArt.canvasWidth) * dot / 2).rounded()
        let originY = (feet.y - CGFloat(PixelCharacterArt.canvasHeight) * dot).rounded()
        let origin = CGPoint(x: originX, y: originY)

        func place(_ x: Int, _ y: Int) -> CGPoint {
            CGPoint(x: origin.x + CGFloat(x) * dot, y: origin.y + CGFloat(y) * dot)
        }

        drawShadow(in: &context, feet: feet, dot: dot, width: bodyWidth(look) + 4, lift: frame.lift)
        drawAura(in: &context, look: look, feet: feet, dot: dot)

        // 横から見た体は正面より薄い。1 段細い胴を使うだけで「横を向いている」と読める。
        let girth = sideways ? slimmer(look.build.girth) : look.build.girth
        let bodyW = PixelCharacterArt.bodyWidth(girth)
        let armW = PixelCharacterArt.armWidth(look.build.arm)
        let legW = PixelCharacterArt.legWidth(look.build.leg)

        let bodyX = Anchor.centerX - bodyW / 2
        // 上半身は「浮き」と「しゃがみ」の両方で上下する。脚は接地したまま。
        let upperY = frame.lift + frame.crouch

        // 脚。正面・背面は左右に並べ、横向きは重ねて前後に開く（横から見ると脚は並ばない）。
        let legSprite = PixelCharacterArt.leg(look.build.leg)
        let legSlots: [(x: Int, lift: Int)] = sideways
            ? [
                // 奥の脚を先に、手前の脚を後に描く。
                // 奥の足は 1 ドット持ち上げる。同じ高さに並べると靴が横一列につながって、
                // 足ではなく板を履いているように見えるため。
                (Anchor.centerX - legW / 2 - frame.legStride, frame.legStride == 0 ? 0 : 1),
                (Anchor.centerX - legW / 2 + frame.legStride, 0),
            ]
            : [
                (Anchor.centerX - legW, frame.leftLegLift),
                (Anchor.centerX, frame.rightLegLift),
            ]
        for (index, slot) in legSlots.enumerated() {
            // 横向きの奥側の脚は影色で沈めて、2 本が重なって見えるようにする。
            let legPalette = (sideways && index == 0) ? palette.recessed : palette
            context.drawPixels(legSprite, at: place(slot.x, Anchor.legY - slot.lift), dot: dot, palette: legPalette, flipped: mirrored)
        }

        // リュック（胴の後ろ）。
        if look.carriesPack {
            let packW = PixelCharacterArt.backpack.width
            let packX = sideways
                ? (mirrored ? bodyX + bodyW - 2 : bodyX + 2 - packW)
                : Anchor.centerX - packW / 2
            context.drawPixels(
                PixelCharacterArt.backpack,
                at: place(packX, Anchor.bodyY + 1 + upperY), dot: dot, palette: palette, flipped: mirrored
            )
        }

        // 腕。横向きでは手前の腕しか見えないので、奥の腕は胴の後ろに影色で置く。
        let armSprite = PixelCharacterArt.arm(look.build.arm)
        let armPositions = armAnchors(
            bodyX: bodyX, bodyW: bodyW, armW: armW, frame: frame, upperY: upperY, sideways: sideways
        )
        if sideways {
            if let far = armPositions.first {
                context.drawPixels(armSprite, at: place(far.x, far.y), dot: dot, palette: palette.recessed, flipped: mirrored)
            }
        } else {
            for anchor in armPositions {
                context.drawPixels(armSprite, at: place(anchor.x, anchor.y), dot: dot, palette: palette, flipped: mirrored)
            }
        }

        // 胴。
        context.drawPixels(
            PixelCharacterArt.body(look.build.girth),
            at: place(bodyX, Anchor.bodyY + upperY), dot: dot, palette: palette, flipped: mirrored
        )

        // 横向きの手前の腕は胴より前に出す。
        if sideways, let near = armPositions.last {
            context.drawPixels(armSprite, at: place(near.x, near.y), dot: dot, palette: palette, flipped: mirrored)
        }

        // 頭。向きが変わるのはここ。
        // コーチは帽子付きの専用スプライト。プレイヤーは **素体 → 髪 → アクセサリー** の 3 層で描き、
        // 髪型とアクセサリーを着せ替えられるようにする。
        let headY = Anchor.headY + upperY
        let headOrigin = place(Anchor.headX, headY)
        if look.role == .coach {
            context.drawPixels(
                PixelCharacterArt.coachHead(blinking: frame.blinking),
                at: headOrigin, dot: dot, palette: palette, flipped: mirrored
            )
        } else {
            context.drawPixels(
                PixelHairArt.headBase(facing: facing, blinking: frame.blinking),
                at: headOrigin, dot: dot, palette: palette, flipped: mirrored
            )
            context.drawPixels(
                PixelHairArt.hair(styleId: look.hairStyleId, facing: facing),
                at: headOrigin, dot: dot, palette: palette, flipped: mirrored
            )
            if let accessory = PixelHairArt.accessorySprite(id: look.accessoryId, facing: facing) {
                context.drawPixels(accessory, at: headOrigin, dot: dot, palette: palette, flipped: mirrored)
            }
        }

        // コーチのクリップボード。腕の外側に垂らす（内側に置くと胴に重なって読めない）。
        if look.role == .coach, let hand = armPositions.last {
            context.drawPixels(
                PixelCharacterArt.clipboard,
                at: place(hand.x, hand.y + PixelCharacterArt.armHeight - 3),
                dot: dot, palette: palette
            )
        }

        // 装備と小道具（体の上に重ねる）。横向きでは手前の手にだけ持たせる。
        let handAnchors = sideways ? Array(armPositions.suffix(1)) : armPositions

        if frame.holdsDumbbell {
            for anchor in handAnchors {
                let handX = anchor.x + armW / 2 - 2
                let handY = anchor.y + PixelCharacterArt.armHeight - 1
                context.drawPixels(PixelCharacterArt.dumbbell, at: place(handX, handY), dot: dot, palette: palette)
            }
        }

        if let hand = look.equipped[.hand] {
            palette.accent = rarityColor(hand.rarity)
            let sprite = PixelCharacterArt.handGear(hand.rarity)
            for anchor in handAnchors {
                let handX = anchor.x + (armW - sprite.width) / 2
                let handY = anchor.y + PixelCharacterArt.armHeight - sprite.height
                context.drawPixels(sprite, at: place(handX, handY), dot: dot, palette: palette)
            }
        }

        if let waist = look.equipped[.waist] {
            palette.accent = rarityColor(waist.rarity)
            drawBelt(in: &context, at: place(bodyX, Anchor.bodyY + 6 + upperY), width: bodyW, dot: dot, color: rarityColor(waist.rarity))
        }

        if let headItem = look.equipped[.head] {
            palette.accent = rarityColor(headItem.rarity)
            let sprite = PixelCharacterArt.headGear(headItem.rarity)
            let offset = PixelCharacterArt.headGearOffset(headItem.rarity)
            context.drawPixels(sprite, at: place(Anchor.headX, headY + offset), dot: dot, palette: palette, flipped: mirrored)
        }

        if let name = look.nameTag {
            drawNameTag(in: &context, name: name, at: place(Anchor.centerX, headY - 3), dot: dot)
        }
    }

    // MARK: - 腕の位置

    private struct ArmAnchor {
        let x: Int
        let y: Int
    }

    /// 腕の左上位置。返り値は [奥, 手前] の順（横向きで描き分けるため）。
    /// 挙げているときは肩の上に出す。
    private static func armAnchors(
        bodyX: Int, bodyW: Int, armW: Int,
        frame: PixelCharacterLayout.Frame, upperY: Int, sideways: Bool
    ) -> [ArmAnchor] {
        let baseY = frame.armsRaised
            ? Anchor.bodyY - PixelCharacterArt.armHeight + 2 + upperY
            : Anchor.armY + upperY

        guard sideways else {
            // 内側の輪郭を胴の輪郭に 1 ドット重ねる。重ねないと黒い線が 2 本並んで腕が太く暗く見える。
            return [
                ArmAnchor(x: bodyX - armW + 1 + frame.leftArmX, y: baseY + frame.leftArmY),
                ArmAnchor(x: bodyX + bodyW - 1 + frame.rightArmX, y: baseY + frame.rightArmY),
            ]
        }

        // 横向きは腕が前後に並ぶ。胴の中央付近に重ね、歩幅ぶんだけ前後にずらす。
        let center = Anchor.centerX - armW / 2
        return [
            ArmAnchor(x: center - frame.legStride, y: baseY + frame.leftArmY),
            ArmAnchor(x: center + frame.legStride, y: baseY + frame.rightArmY),
        ]
    }

    private static func bodyWidth(_ look: Look) -> Int {
        PixelCharacterArt.bodyWidth(look.build.girth)
    }

    /// 1 段細い胴。横向きのときに使う。
    private static func slimmer(_ girth: CharacterBuild.Girth) -> CharacterBuild.Girth {
        switch girth {
        case .wide: return .normal
        case .normal, .slim: return .slim
        }
    }

    // MARK: - 影・オーラ・ベルト・名札

    /// 接地の影。ドット絵に合わせて楕円ではなく矩形 2 段で作る。
    private static func drawShadow(in context: inout GraphicsContext, feet: CGPoint, dot: CGFloat, width: Int, lift: Int) {
        let shrink = lift < 0 ? 1 : 0
        let w = max(2, width - shrink * 2)
        let x = (feet.x - CGFloat(w) * dot / 2).rounded()
        let y = (feet.y - dot).rounded()
        let color = Color.black.opacity(0.22)
        context.fill(Path(CGRect(x: x, y: y, width: CGFloat(w) * dot, height: dot)), with: .color(color))
        context.fill(
            Path(CGRect(x: x + dot, y: y - dot, width: CGFloat(w - 2) * dot, height: dot)),
            with: .color(color.opacity(0.5))
        )
    }

    /// オーラ。ドット絵なのでグラデーションではなく、点滅する光の粒で表す。
    private static func drawAura(in context: inout GraphicsContext, look: Look, feet: CGPoint, dot: CGFloat) {
        let item = look.equipped[.aura]
        let strength = max(look.appearance01, item != nil ? 0.7 : 0)
        guard strength > 0.2 else { return }
        let color = item.map { rarityColor($0.rarity) } ?? Theme.lime
        // 体の周りの決まった位置に粒を置く（毎フレーム動かすと目が疲れるので位置は固定）。
        let spots: [(Int, Int)] = [(-2, -20), (26, -18), (-1, -10), (25, -8), (12, -25)]
        for (index, spot) in spots.enumerated() {
            let size = index % 2 == 0 ? dot : dot * 2
            let x = (feet.x - CGFloat(PixelCharacterArt.canvasWidth) * dot / 2 + CGFloat(spot.0) * dot).rounded()
            let y = (feet.y + CGFloat(spot.1) * dot).rounded()
            context.fill(
                Path(CGRect(x: x, y: y, width: size, height: size)),
                with: .color(color.opacity(0.35 + 0.45 * strength))
            )
        }
    }

    private static func drawBelt(in context: inout GraphicsContext, at origin: CGPoint, width: Int, dot: CGFloat, color: Color) {
        context.fill(
            Path(CGRect(x: origin.x, y: origin.y, width: CGFloat(width) * dot, height: dot)),
            with: .color(color)
        )
        // バックル。
        context.fill(
            Path(CGRect(x: origin.x + CGFloat(width / 2 - 1) * dot, y: origin.y, width: dot * 2, height: dot)),
            with: .color(.white)
        )
    }

    private static func drawNameTag(in context: inout GraphicsContext, name: String, at point: CGPoint, dot: CGFloat) {
        let text = context.resolve(
            Text(name)
                .font(.system(size: max(8, dot * 3), weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
        )
        let size = text.measure(in: CGSize(width: dot * 40, height: dot * 8))
        let box = CGRect(
            x: (point.x - size.width / 2 - dot).rounded(),
            y: (point.y - size.height).rounded(),
            width: (size.width + dot * 2).rounded(),
            height: (size.height + dot).rounded()
        )
        context.fill(Path(box), with: .color(.black.opacity(0.55)))
        context.draw(text, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
    }

    // MARK: - 色

    static func rarityColor(_ rarity: Expedition.Rarity) -> Color {
        switch rarity {
        case .common: return Color(hexF: 0xC9CFC4)
        case .rare: return Theme.info
        case .epic: return Theme.warning
        }
    }
}

private extension PixelCharacterRenderer.Look {
    /// 進化段階から求めるオーラの強さ（0...1）。
    var appearance01: Double {
        let count = max(1, CharacterProgress.Stage.allCases.count - 1)
        return Double(stage.rawValue) / Double(count)
    }
}
