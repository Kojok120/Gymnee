import SwiftUI

/// ドット絵キャラの合成と描画。
///
/// パーツ（頭・胴・腕・脚）を `PixelCharacterLayout.Frame` のずらし量どおりに重ねる。
/// **座標はすべて整数ドット**で計算し、最後にドットの一辺（pt）を掛けて画面座標にする。
/// 途中で小数を挟むとドットの境目がにじんで、ドット絵に見えなくなる。
enum PixelCharacterRenderer {

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
    }

    // MARK: - 画枠の基準位置（ドット）

    private enum Anchor {
        /// 頭の左上。
        static let headX = 5
        static let headY = 0
        /// 胴の上端。
        static let bodyY = 12
        /// 腕の上端。
        static let armY = 13
        /// 脚の上端。
        static let legY = 20
        /// 画枠の横中心。
        static let centerX = 12
    }

    // MARK: - 描画

    /// キャラ 1 体を描く。`feet` は接地点（画面座標）、`dot` は 1 ドットの一辺（pt）。
    static func draw(
        in context: inout GraphicsContext,
        look: Look,
        frame: PixelCharacterLayout.Frame,
        facingRight: Bool,
        feet: CGPoint,
        dot: CGFloat
    ) {
        guard dot > 0 else { return }
        var palette = PixelPalette.make(skin: look.skin)

        // 画枠の左上（＝足元から左へ半分、上へ画枠の高さぶん）。ドット境界に吸着させる。
        let originX = (feet.x - CGFloat(PixelCharacterArt.canvasWidth) * dot / 2).rounded()
        let originY = (feet.y - CGFloat(PixelCharacterArt.canvasHeight) * dot).rounded()
        let origin = CGPoint(x: originX, y: originY)

        func place(_ x: Int, _ y: Int) -> CGPoint {
            CGPoint(x: origin.x + CGFloat(x) * dot, y: origin.y + CGFloat(y) * dot)
        }

        drawShadow(in: &context, feet: feet, dot: dot, width: bodyWidth(look) + 4, lift: frame.lift)
        drawAura(in: &context, look: look, feet: feet, dot: dot)

        let bodyW = bodyWidth(look)
        let armW = PixelCharacterArt.armWidth(look.build.arm)
        let legW = PixelCharacterArt.legWidth(look.build.leg)

        let bodyX = Anchor.centerX - bodyW / 2
        // 上半身は「浮き」と「しゃがみ」の両方で上下する。脚は接地したまま。
        let upperY = frame.lift + frame.crouch

        // 脚（胴の後ろに置く）。
        let legSprite = PixelCharacterArt.leg(look.build.leg)
        for (legX, lift) in [(Anchor.centerX - legW, frame.leftLegLift), (Anchor.centerX, frame.rightLegLift)] {
            context.drawPixels(legSprite, at: place(legX, Anchor.legY - lift), dot: dot, palette: palette, flipped: !facingRight)
        }

        // リュック（胴の後ろ）。
        if look.carriesPack {
            let packX = facingRight ? bodyX - 4 : bodyX + bodyW - 2
            context.drawPixels(
                PixelCharacterArt.backpack,
                at: place(packX, Anchor.bodyY + 1 + upperY), dot: dot, palette: palette, flipped: !facingRight
            )
        }

        // 腕。
        let armSprite = PixelCharacterArt.arm(look.build.arm)
        let armPositions = armAnchors(bodyX: bodyX, bodyW: bodyW, armW: armW, frame: frame, upperY: upperY)
        for anchor in armPositions {
            context.drawPixels(armSprite, at: place(anchor.x, anchor.y), dot: dot, palette: palette, flipped: !facingRight)
        }

        // 胴。
        context.drawPixels(
            PixelCharacterArt.body(look.build.girth),
            at: place(bodyX, Anchor.bodyY + upperY), dot: dot, palette: palette, flipped: !facingRight
        )

        // 頭。
        let headSprite = frame.blinking ? PixelCharacterArt.headBlink : PixelCharacterArt.head
        let headY = Anchor.headY + upperY
        context.drawPixels(headSprite, at: place(Anchor.headX, headY), dot: dot, palette: palette, flipped: !facingRight)

        // 装備と小道具（体の上に重ねる）。
        if frame.holdsDumbbell {
            for anchor in armPositions {
                let handX = anchor.x + armW / 2 - 2
                let handY = anchor.y + PixelCharacterArt.armHeight - 1
                context.drawPixels(PixelCharacterArt.dumbbell, at: place(handX, handY), dot: dot, palette: palette)
            }
        }

        if let hand = look.equipped[.hand] {
            palette.accent = rarityColor(hand.rarity)
            let sprite = PixelCharacterArt.handGear(hand.rarity)
            for anchor in armPositions {
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
            context.drawPixels(sprite, at: place(Anchor.headX, headY + offset), dot: dot, palette: palette, flipped: !facingRight)
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

    /// 左右の腕の左上位置。挙げているときは肩の上に出す。
    private static func armAnchors(
        bodyX: Int, bodyW: Int, armW: Int,
        frame: PixelCharacterLayout.Frame, upperY: Int
    ) -> [ArmAnchor] {
        let baseY = frame.armsRaised
            ? Anchor.bodyY - PixelCharacterArt.armHeight + 2 + upperY
            : Anchor.armY + upperY
        // 内側の輪郭を胴の輪郭に 1 ドット重ねる。重ねないと黒い線が 2 本並んで腕が太く暗く見える。
        return [
            ArmAnchor(x: bodyX - armW + 1 + frame.leftArmX, y: baseY + frame.leftArmY),
            ArmAnchor(x: bodyX + bodyW - 1 + frame.rightArmX, y: baseY + frame.rightArmY),
        ]
    }

    private static func bodyWidth(_ look: Look) -> Int {
        PixelCharacterArt.bodyWidth(look.build.girth)
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
