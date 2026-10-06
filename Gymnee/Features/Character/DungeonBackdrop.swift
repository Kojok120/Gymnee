import SwiftUI

/// 週ボスの戦闘画面の背景（issue #137）。石壁のボス部屋。
///
/// 部屋（`RoomBackdrop`）と同じく、**すべての形をドット格子に吸着させる**。
/// 毎フレーム描き直す松明の炎・ボス・仲間とは分けた静的なレイヤー。
struct DungeonBackdrop: View {
    /// 壁と床の境目（0...1、View の高さに対する割合）。
    let horizon: CGFloat
    /// 1 ドットの一辺（pt）。仲間のキャラと同じ値を使う。
    let dot: CGFloat
    /// 奥の通路にさす色（ボスの体色）。ボスごとに部屋の空気を変える。
    let bossTint: Color
    /// 松明を置く横位置（0...1）。炎は `PixelDungeonArt.flame` を上に重ねる。
    static let torchXs: [CGFloat] = [0.13, 0.87]
    /// 松明の受け皿の高さ（壁の高さに対する割合。上から）。
    static let torchY: CGFloat = 0.42

    var body: some View {
        Canvas { context, size in
            let cols = (size.width / dot).rounded(.up)
            let rows = (size.height / dot).rounded(.up)
            let horizonRow = ((size.height * horizon) / dot).rounded()
            drawWall(&context, cols: cols, horizonRow: horizonRow)
            drawArch(&context, cols: cols, horizonRow: horizonRow)
            drawFloor(&context, cols: cols, rows: rows, horizonRow: horizonRow)
            drawTorchBrackets(&context, cols: cols, horizonRow: horizonRow)
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }

    // MARK: - 色（ドット絵の配色。テーマのトークンではなく絵の一部として持つ）

    private static let wall = Color(hexF: 0x2E3240)
    private static let wallLight = Color(hexF: 0x363B4B)
    private static let wallDark = Color(hexF: 0x272A36)
    private static let mortar = Color(hexF: 0x1B1E27)
    private static let archHole = Color(hexF: 0x0D0F15)
    private static let archStone = Color(hexF: 0x4A5064)
    private static let archShade = Color(hexF: 0x3A3F50)
    // 床は壁より暖かい土色の石にして、壁と床の境をはっきりさせる。
    private static let floor = Color(hexF: 0x4A4239)
    private static let floorLight = Color(hexF: 0x564C41)
    private static let floorJoint = Color(hexF: 0x2E2924)
    static let glow = Color(hexF: 0xFFB347)

    private func fill(_ context: inout GraphicsContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, _ color: Color) {
        guard w > 0, h > 0 else { return }
        context.fill(Path(CGRect(x: x * dot, y: y * dot, width: w * dot, height: h * dot)), with: .color(color))
    }

    // MARK: - 壁

    /// 石を積んだ壁。段ごとに目地をずらし、石の明るさを3段で散らす（同じ並びが続かないよう座標で決める）。
    private func drawWall(_ context: inout GraphicsContext, cols: CGFloat, horizonRow: CGFloat) {
        fill(&context, x: 0, y: 0, w: cols, h: horizonRow, Self.wall)
        let brickH: CGFloat = 6
        let brickW: CGFloat = 12
        var y: CGFloat = 0
        var course = 0
        while y < horizonRow {
            let offset: CGFloat = course % 2 == 0 ? 0 : brickW / 2
            var x = -offset
            var index = 0
            while x < cols {
                let shade = (course * 7 + index * 3) % 5
                if shade == 0 { fill(&context, x: x + 1, y: y + 1, w: brickW - 1, h: brickH - 1, Self.wallLight) }
                if shade == 3 { fill(&context, x: x + 1, y: y + 1, w: brickW - 1, h: brickH - 1, Self.wallDark) }
                fill(&context, x: x, y: y, w: 1, h: brickH, Self.mortar)
                x += brickW
                index += 1
            }
            fill(&context, x: 0, y: y, w: cols, h: 1, Self.mortar)
            y += brickH
            course += 1
        }
        // 壁の根元の影。床との境を締める。
        fill(&context, x: 0, y: horizonRow - 2, w: cols, h: 2, Self.mortar)
    }

    /// 奥へ続く通路のアーチ。ボスはこの前に立つ。内側にボスの色をうっすら差す。
    private func drawArch(_ context: inout GraphicsContext, cols: CGFloat, horizonRow: CGFloat) {
        let width = (cols * 0.44).rounded()
        let left = ((cols - width) / 2).rounded()
        let height = (horizonRow * 0.62).rounded()
        let top = horizonRow - height
        // 石の縁（2ドット）と、階段状に丸めた天井。
        let steps: [CGFloat] = [8, 5, 3, 2, 1, 1]
        for (row, inset) in steps.enumerated() {
            fill(&context, x: left + inset - 2, y: top + CGFloat(row), w: width - inset * 2 + 4, h: 1, Self.archStone)
        }
        fill(&context, x: left - 2, y: top + CGFloat(steps.count), w: width + 4, h: height - CGFloat(steps.count), Self.archStone)
        for (row, inset) in steps.enumerated() {
            fill(&context, x: left + inset, y: top + CGFloat(row) + 2, w: width - inset * 2, h: 1, Self.archHole)
        }
        fill(&context, x: left, y: top + CGFloat(steps.count) + 2, w: width, h: height - CGFloat(steps.count) - 2, Self.archHole)
        // 縁の影（右側）。
        fill(&context, x: left + width, y: top + CGFloat(steps.count), w: 2, h: height - CGFloat(steps.count), Self.archShade)
        // 奥の気配。下ほど濃く、ボスの色を段で重ねる。
        for band in 0..<4 {
            let bandTop = horizonRow - CGFloat(band + 1) * (height * 0.14).rounded()
            fill(&context, x: left + 1, y: bandTop, w: width - 2, h: horizonRow - bandTop,
                 bossTint.opacity(0.05))
        }
    }

    // MARK: - 床

    /// 石畳。奥ほど段を薄くして奥行きを出す。目地は段ごとにずらす。
    private func drawFloor(_ context: inout GraphicsContext, cols: CGFloat, rows: CGFloat, horizonRow: CGFloat) {
        fill(&context, x: 0, y: horizonRow, w: cols, h: rows - horizonRow, Self.floor)
        var y = horizonRow
        var depth: CGFloat = 3
        var course = 0
        while y < rows {
            let width = depth * 3 + 6
            let offset: CGFloat = course % 2 == 0 ? 0 : (width / 2).rounded()
            var x = -offset
            var index = 0
            while x < cols {
                if (course + index) % 3 == 0 {
                    fill(&context, x: x + 1, y: y + 1, w: width - 1, h: depth - 1, Self.floorLight)
                }
                fill(&context, x: x, y: y, w: 1, h: depth, Self.floorJoint)
                x += width
                index += 1
            }
            fill(&context, x: 0, y: y, w: cols, h: 1, Self.floorJoint)
            y += depth
            depth += 1
            course += 1
        }
    }

    // MARK: - 松明の受け皿

    private func drawTorchBrackets(_ context: inout GraphicsContext, cols: CGFloat, horizonRow: CGFloat) {
        let sprite = PixelDungeonArt.bracket
        for ratio in Self.torchXs {
            let x = (cols * ratio).rounded() - CGFloat(sprite.width / 2)
            let y = (horizonRow * Self.torchY).rounded()
            // 壁に落ちる灯り。行ごとに幅を変えた円を段で重ねる（ぼかしは使わない）。
            for (radius, opacity) in [(11, 0.05), (7, 0.07), (4, 0.09)] {
                for dy in -radius...radius {
                    let half = (Double(radius * radius - dy * dy)).squareRoot().rounded()
                    fill(&context, x: x + 3 - CGFloat(half), y: y - 4 + CGFloat(dy), w: CGFloat(half) * 2 + 1, h: 1,
                         Self.glow.opacity(opacity))
                }
            }
            context.drawPixels(sprite, at: CGPoint(x: x * dot, y: y * dot), dot: dot, palette: PixelDungeonArt.palette)
        }
    }
}

/// 戦闘画面の小物のドット絵（issue #137）。**絵を足したら `PixelArtGallery` と `PixelCharacterTests.allSprites` にも足すこと。**
enum PixelDungeonArt {

    /// 松明の受け皿（壁に固定）。炎はこの上に重ねる。
    static let bracket = PixelSprite([
        ".ommmmo",
        ".odddo.",
        "..odo..",
        "..odo..",
        "..odo..",
        "..ooo..",
    ])

    /// 松明の炎。3コマを入れ替えて揺らす。
    static let flameFrames: [PixelSprite] = [
        PixelSprite([
            "...l...",
            "..lrl..",
            "..rlr..",
            ".rrlrr.",
            ".rlllr.",
            "rRlllRr",
            ".RRrRR.",
            "..RRR..",
        ]),
        PixelSprite([
            "..l....",
            "..rl...",
            ".rlr...",
            ".rrlrr.",
            ".rlllr.",
            "rRlllRr",
            ".RRrRR.",
            "..RRR..",
        ]),
        PixelSprite([
            "....l..",
            "...lr..",
            "...rlr.",
            ".rrlrr.",
            ".rlllr.",
            "rRlllRr",
            ".RRrRR.",
            "..RRR..",
        ]),
    ]

    /// 斬撃。攻撃が当たった瞬間にボスへ重ねる。
    static let slash = PixelSprite([
        "..........ll",
        ".........lll",
        "........lll.",
        ".......lll..",
        "......lll...",
        ".....lll....",
        "....lll.....",
        "...lll......",
        "..lll.......",
        ".lll........",
        "lll.........",
        "ll..........",
    ])

    /// 怒りマーク。HP が半分を切ったボスの頭に出す。
    static let anger = PixelSprite([
        ".r.r.",
        "rr.rr",
        ".....",
        "rr.rr",
        ".r.r.",
    ])

    /// 炎と小物の配色。差し色が炎の橙、その影が赤、ハイライトが黄白。
    static let palette: PixelPalette = {
        var palette = PixelPalette.neutral
        palette.accent = Color(hexF: 0xFF9F1C)
        palette.accentShade = Color(hexF: 0xE4572E)
        palette.light = Color(hexF: 0xFFF3B0)
        palette.metal = Color(hexF: 0x8A8F99)
        palette.dark = Color(hexF: 0x5B4636)
        return palette
    }()

    /// 怒りマークの配色。
    static let angerPalette: PixelPalette = {
        var palette = PixelPalette.neutral
        palette.accent = Color(hexF: 0xFF3B30)
        return palette
    }()

    /// 斬撃の配色（白く光る）。
    static let slashPalette: PixelPalette = {
        var palette = PixelPalette.neutral
        palette.light = Color(hexF: 0xFFFFFF)
        return palette
    }()

    /// 被弾の瞬間の白抜き。ボスの全ドットを白で塗る。
    static let flashPalette: PixelPalette = {
        var palette = PixelPalette.neutral
        let white = Color(hexF: 0xFFFFFF)
        palette.outline = white
        palette.accent = white
        palette.accentShade = white
        palette.light = white
        palette.eye = white
        palette.dark = white
        palette.metal = white
        palette.wood = white
        palette.cloth = white
        palette.skin = white
        palette.skinShade = white
        return palette
    }()
}
