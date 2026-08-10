import SwiftUI

/// キャラが暮らす部屋（背景）。ドット絵。
///
/// 毎フレーム描き直すキャラとは分けて、変化したときだけ描き直す静的なレイヤーにしている。
/// **すべての形をドット格子に吸着させる**のが要点で、1 か所でも中途半端な小数座標を混ぜると
/// そこだけ輪郭が滲んで、画面全体がドット絵に見えなくなる。
///
/// 部屋は続けた分だけ賑やかになる: 進化段階で家具が増え、持ち帰った戦利品が棚に並ぶ。
/// グラフを読ませなくても「積み上がっている」ことが目で分かるのが狙い。
struct RoomBackdrop: View {
    let timeOfDay: CharacterScene.TimeOfDay
    let stage: CharacterProgress.Stage
    /// 棚に飾る戦利品（新しい順、先頭から最大 6 個）。
    let shelfItems: [Expedition.Item]
    /// 壁と床の境目（0...1、View の高さに対する割合）。
    let horizon: CGFloat
    /// 1 ドットの一辺（pt）。キャラと必ず同じ値を使う。
    let dot: CGFloat

    var body: some View {
        Canvas { context, size in
            let horizonRow = ((size.height * horizon) / dot).rounded()
            drawWall(&context, size: size, horizonRow: horizonRow)
            drawFloor(&context, size: size, horizonRow: horizonRow)
            drawWindow(&context, size: size, horizonRow: horizonRow)
            drawShelf(&context, size: size, horizonRow: horizonRow)
            drawFurniture(&context, size: size, horizonRow: horizonRow)
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }

    /// ドット単位の矩形を描く（座標は必ずドット格子に乗る）。
    private func fill(_ context: inout GraphicsContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, _ color: Color) {
        guard w > 0, h > 0 else { return }
        context.fill(
            Path(CGRect(x: x * dot, y: y * dot, width: w * dot, height: h * dot)),
            with: .color(color)
        )
    }

    private func columns(_ size: CGSize) -> CGFloat { (size.width / dot).rounded(.up) }
    private func rows(_ size: CGSize) -> CGFloat { (size.height / dot).rounded(.up) }

    // MARK: - 壁と床

    private func drawWall(_ context: inout GraphicsContext, size: CGSize, horizonRow: CGFloat) {
        let cols = columns(size)
        fill(&context, x: 0, y: 0, w: cols, h: horizonRow, wallColor)

        // 壁のタイル目地。等間隔の 1 ドット線で、のっぺりさせない。
        var y: CGFloat = 4
        while y < horizonRow - 2 {
            fill(&context, x: 0, y: y, w: cols, h: 1, wallLine)
            y += 8
        }
        // 幅木。
        fill(&context, x: 0, y: horizonRow - 2, w: cols, h: 2, baseboardColor)
    }

    private func drawFloor(_ context: inout GraphicsContext, size: CGSize, horizonRow: CGFloat) {
        let cols = columns(size)
        let allRows = rows(size)
        fill(&context, x: 0, y: horizonRow, w: cols, h: allRows - horizonRow, floorColor)

        // 床板。奥ほど間隔を詰めて奥行きを出す（ドット絵の定番）。
        var y = horizonRow + 3
        var gap: CGFloat = 3
        while y < allRows {
            fill(&context, x: 0, y: y, w: cols, h: 1, floorLine)
            gap += 1
            y += gap
        }
        // 縦の目地は 2 本だけ。多いとキャラが読みにくくなる。
        for ratio in [0.28, 0.72] {
            let x = (cols * CGFloat(ratio)).rounded()
            fill(&context, x: x, y: horizonRow, w: 1, h: allRows - horizonRow, floorLine)
        }

        // トレーニングマット。床が広いままだと単調なので、生活の痕跡を 1 枚置く。
        // 主役はキャラなので、彩度は床から少しずらす程度に留める。
        let matW = (cols * 0.42).rounded()
        let matH: CGFloat = 11
        let matX = ((cols - matW) / 2).rounded()
        let matY = (horizonRow + (allRows - horizonRow) * 0.34).rounded()
        fill(&context, x: matX, y: matY, w: matW, h: matH, matColor)
        fill(&context, x: matX, y: matY, w: matW, h: 1, matEdge)
        fill(&context, x: matX, y: matY + matH - 1, w: matW, h: 1, matEdge)
        fill(&context, x: matX, y: matY, w: 1, h: matH, matEdge)
        fill(&context, x: matX + matW - 1, y: matY, w: 1, h: matH, matEdge)
        // 表面の目地。ベタ塗りのままだと板に見える。
        fill(&context, x: matX + 2, y: matY + (matH / 2).rounded(), w: matW - 4, h: 1, matEdge)
    }

    // MARK: - 窓

    private func drawWindow(_ context: inout GraphicsContext, size: CGSize, horizonRow: CGFloat) {
        // 窓は画面比ではなく**ドット数で固定**する。比率で決めると端末が大きいほど窓も巨大になり、
        // キャラとの縮尺が合わなくなるため。
        let w: CGFloat = 26
        let h = min(22, max(12, horizonRow - 12))
        let x: CGFloat = 6
        let y = max(3, ((horizonRow - h) / 2).rounded())

        // 外の空（上下 2 段のベタで空気感を出す）。
        fill(&context, x: x, y: y, w: w, h: (h / 2).rounded(), skyTop)
        fill(&context, x: x, y: y + (h / 2).rounded(), w: w, h: h - (h / 2).rounded(), skyBottom)

        // 太陽 / 月（3 × 3 ドット）。
        let orbX = x + (w * 0.68).rounded()
        let orbY = y + (h * (timeOfDay == .day ? 0.18 : 0.30)).rounded()
        fill(&context, x: orbX, y: orbY, w: 3, h: 3, orbColor)
        fill(&context, x: orbX - 1, y: orbY + 1, w: 5, h: 1, orbColor)
        fill(&context, x: orbX + 1, y: orbY - 1, w: 1, h: 5, orbColor)

        // 夜は星。位置は固定＝毎晩おなじ夜空。
        if timeOfDay == .night {
            var rng = DeterministicRandom(seed: 0x5741_5254)
            for _ in 0..<10 {
                let sx = x + (CGFloat(rng.unit()) * (w - 1)).rounded()
                let sy = y + (CGFloat(rng.unit()) * (h * 0.7)).rounded()
                fill(&context, x: sx, y: sy, w: 1, h: 1, .white.opacity(0.8))
            }
        }

        // 窓枠（1 ドットの輪郭）と桟。
        fill(&context, x: x - 1, y: y - 1, w: w + 2, h: 1, frameColor)
        fill(&context, x: x - 1, y: y + h, w: w + 2, h: 1, frameColor)
        fill(&context, x: x - 1, y: y - 1, w: 1, h: h + 2, frameColor)
        fill(&context, x: x + w, y: y - 1, w: 1, h: h + 2, frameColor)
        fill(&context, x: x + (w / 2).rounded(), y: y, w: 1, h: h, frameColor)
        fill(&context, x: x, y: y + (h / 2).rounded(), w: w, h: 1, frameColor)

        // 窓から床へ落ちる光。段を細かく刻んで、塊ではなく「広がり」に見せる。
        // 帯どうしを重ねない（重ねると α が積もって濃い段差になる）。
        guard timeOfDay != .night else { return }
        for step in 0..<8 {
            let spread = CGFloat(step)
            let top = horizonRow + CGFloat(step) * 3
            fill(&context, x: x - spread, y: top, w: w + spread * 2, h: 3, beamColor)
        }
    }

    // MARK: - 棚（戦利品を飾る）

    private func drawShelf(_ context: inout GraphicsContext, size: CGSize, horizonRow: CGFloat) {
        guard !shelfItems.isEmpty else { return }
        let cols = columns(size)
        let x = (cols * 0.52).rounded()
        let w = (cols * 0.40).rounded()
        let y = (horizonRow * 0.56).rounded()

        fill(&context, x: x, y: y, w: w, h: 1, shelfLight)
        fill(&context, x: x, y: y + 1, w: w, h: 1, shelfColor)

        // 戦利品は 2 × 3 ドットの小瓶として並べる（アイコンを縮めるより読みやすい）。
        let items = Array(shelfItems.prefix(6))
        let slot = w / CGFloat(max(1, items.count))
        for (index, item) in items.enumerated() {
            let ix = (x + slot * CGFloat(index) + (slot / 2).rounded() - 1).rounded()
            let color = PixelCharacterRenderer.rarityColor(item.rarity)
            fill(&context, x: ix, y: y - 3, w: 2, h: 3, color)
            fill(&context, x: ix, y: y - 4, w: 2, h: 1, color.opacity(0.65))
        }
    }

    // MARK: - 家具（続けた分だけ増える）

    private func drawFurniture(_ context: inout GraphicsContext, size: CGSize, horizonRow: CGFloat) {
        let cols = columns(size)
        var palette = PixelPalette.make(skin: SkinCatalog.all[0])
        palette.wood = shelfColor

        // 奥の壁ぎわに並べる。キャラは必ず手前を歩くので重ならない。
        func place(_ sprite: PixelSprite, ratio: CGFloat) {
            let x = ((cols * ratio).rounded() * dot).rounded()
            let y = ((horizonRow + 1) * dot - CGFloat(sprite.height) * dot).rounded()
            context.drawPixels(sprite, at: CGPoint(x: x, y: y), dot: dot, palette: palette)
        }

        // ルーキーから置いてある観葉植物。部屋が空っぽに見えないように。
        // 端に寄せすぎると見切れるので、いちばん左でも余白を残す。
        place(PixelCharacterArt.plant, ratio: 0.10)
        if stage >= .trainee { place(PixelCharacterArt.dumbbellRack, ratio: 0.30) }
        if stage >= .challenger { place(PixelCharacterArt.bench, ratio: 0.58) }
        if stage >= .veteran { place(PixelCharacterArt.barbell, ratio: 0.82) }
    }

    // MARK: - 配色

    private var wallColor: Color {
        switch timeOfDay {
        case .dawn: return Color(light: 0xF0DFCE, dark: 0x241E24)
        case .day: return Color(light: 0xE9EFE0, dark: 0x1D231F)
        case .dusk: return Color(light: 0xEDD5C6, dark: 0x261D1F)
        case .night: return Color(light: 0xD2D9E2, dark: 0x161B22)
        }
    }

    private var wallLine: Color { Color(light: 0x000000, dark: 0xFFFFFF).opacity(0.05) }
    private var baseboardColor: Color { Color(light: 0xB7C0A8, dark: 0x2E352F) }
    private var floorColor: Color { Color(light: 0xCDB593, dark: 0x241D17) }
    private var floorLine: Color { Color(light: 0x8A6F4E, dark: 0x120E0B).opacity(0.28) }
    private var matColor: Color { Color(light: 0xB6AE94, dark: 0x2C302B) }
    private var matEdge: Color { Color(light: 0x9A9179, dark: 0x1E221E) }
    private var shelfColor: Color { Color(light: 0xA9865F, dark: 0x5A4934) }
    private var shelfLight: Color { Color(light: 0xC9A87C, dark: 0x76603F) }
    private var frameColor: Color { Color(light: 0xFFFFFF, dark: 0x3A423B) }

    private var skyTop: Color {
        switch timeOfDay {
        case .dawn: return Color(hexF: 0xFFC97B)
        case .day: return Color(hexF: 0x6FC4F5)
        case .dusk: return Color(hexF: 0xE86A4E)
        case .night: return Color(hexF: 0x16213E)
        }
    }

    private var skyBottom: Color {
        switch timeOfDay {
        case .dawn: return Color(hexF: 0xFFE9C4)
        case .day: return Color(hexF: 0xCDEBFB)
        case .dusk: return Color(hexF: 0xFFB27A)
        case .night: return Color(hexF: 0x2B3A63)
        }
    }

    private var orbColor: Color {
        switch timeOfDay {
        case .dawn: return Color(hexF: 0xFFF3D0)
        case .day: return Color(hexF: 0xFFF6C9)
        case .dusk: return Color(hexF: 0xFFE0A3)
        case .night: return Color(hexF: 0xF2F3E4)
        }
    }

    /// 窓から床へ落ちる光。床の色を薄く持ち上げるだけにして、形が主張しないようにする。
    ///
    /// 明色をそのまま重ねるとダークモードでは床とのコントラストが跳ね上がり、
    /// 光ではなく「白いピラミッド」に見えてしまう。暗い側は床に近い色を当てる。
    private var beamColor: Color {
        switch timeOfDay {
        case .dawn: return Color(light: 0xFFD79A, dark: 0x6B5A3C).opacity(0.07)
        case .day: return Color(light: 0xFFFBE8, dark: 0x6E6248).opacity(0.08)
        case .dusk: return Color(light: 0xFF9E6B, dark: 0x6B4736).opacity(0.06)
        case .night: return .clear
        }
    }
}
