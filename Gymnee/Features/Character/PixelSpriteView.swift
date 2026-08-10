import SwiftUI

/// ドット絵を SwiftUI の View として置く。シート・一覧・演出など、Canvas の外で使う用。
///
/// **ドットの一辺は必ず整数 pt に丸める**。指定サイズにぴったり合わせようとして小数倍にすると、
/// ドットの境目がにじんでベクター画像のように見えてしまい、画面の中でここだけ質感が浮く。
struct PixelSpriteView: View {
    let sprite: PixelSprite
    var palette: PixelPalette
    /// 収めたい一辺（pt）。実際の描画はこれ以下の整数倍になる。
    var side: CGFloat = 44
    var flipped: Bool = false

    /// 1 ドットの一辺（整数 pt、最低 1）。
    private var dot: CGFloat {
        let longest = CGFloat(max(sprite.width, sprite.height))
        guard longest > 0 else { return 1 }
        return max(1, (side / longest).rounded(.down))
    }

    var body: some View {
        Canvas { context, size in
            let width = CGFloat(sprite.width) * dot
            let height = CGFloat(sprite.height) * dot
            let origin = CGPoint(
                x: ((size.width - width) / 2).rounded(),
                y: ((size.height - height) / 2).rounded()
            )
            context.drawPixels(sprite, at: origin, dot: dot, palette: palette, flipped: flipped)
        }
        .frame(width: CGFloat(sprite.width) * dot, height: CGFloat(sprite.height) * dot)
        .accessibilityHidden(true)
    }
}

extension PixelPalette {
    /// 装備・戦利品アイコン用のパレット。差し色にレア度の色を入れる。
    static func item(rarity: Expedition.Rarity) -> PixelPalette {
        var palette = make(skin: SkinCatalog.all[0])
        palette.accent = PixelCharacterRenderer.rarityColor(rarity)
        palette.accentShade = palette.accent.mix(with: Color(hexF: 0x2A2320), by: 0.35)
        return palette
    }

    /// 部屋・小物用の中立パレット。
    static let neutral: PixelPalette = make(skin: SkinCatalog.all[0])
}
