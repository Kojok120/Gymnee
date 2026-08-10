import SwiftUI
import UIKit

/// ドット絵 1 枚。**1 文字＝1 ドット**の文字列で持つ。
///
/// 画像ファイルではなくコードで持つ理由:
/// - Git で差分が読める（どのドットを直したかレビューできる）
/// - 色を直接持たず「役割」で持つので、スキンごとにパレットを差し替えられる
/// - 解像度に依存しない（1 ドットを何 pt の矩形で描くかは描画時に決める）
///
/// 行の長さが揃っていないと絵が崩れるので、`PixelSpriteTests` で全スプライトを検証している。
struct PixelSprite: Equatable {
    let width: Int
    let height: Int
    /// 同じ色が横に連続する区間。1 ドットずつ矩形を描くと数が多くなりすぎるため、生成時にまとめる。
    let runs: [Run]

    struct Run: Equatable {
        let x: Int
        let y: Int
        let length: Int
        let ink: Ink
    }

    /// ドットの役割。実際の色は `PixelPalette` が決める。
    enum Ink: Character, CaseIterable {
        /// 透明。
        case none = "."
        /// 輪郭。
        case outline = "o"
        case skin = "s"
        case skinShade = "S"
        case hair = "h"
        case hairShade = "H"
        /// ウェア（タンクトップ）。
        case wear = "w"
        case wearShade = "W"
        /// ショートパンツ。
        case pants = "p"
        case pantsShade = "P"
        case eye = "e"
        /// ハイライト（白）。
        case light = "l"
        case cheek = "c"
        /// 金属（ダンベル・器具）。
        case metal = "m"
        /// 濃い色（シューズ・小物）。
        case dark = "d"
        /// 木（家具・棚）。
        case wood = "k"
        /// 葉（観葉植物）。
        case leaf = "g"
        /// 差し色。装備のレア度など、描くたびに色が変わるものに使う。
        case accent = "r"
    }

    /// 行の文字列からスプライトを組み立てる。未知の文字は透明として扱う（絵が壊れても落とさない）。
    init(_ rows: [String]) {
        height = rows.count
        width = rows.map(\.count).max() ?? 0
        var collected: [Run] = []
        for (y, row) in rows.enumerated() {
            var x = 0
            var current: Ink?
            var start = 0
            for character in row {
                let ink = Ink(rawValue: character) ?? .none
                if ink != current {
                    if let open = current, open != .none, x > start {
                        collected.append(Run(x: start, y: y, length: x - start, ink: open))
                    }
                    current = ink
                    start = x
                }
                x += 1
            }
            if let open = current, open != .none, x > start {
                collected.append(Run(x: start, y: y, length: x - start, ink: open))
            }
        }
        runs = collected
    }

    /// 行の長さがすべて揃っているか（テスト用）。
    static func rowsAreRectangular(_ rows: [String]) -> Bool {
        guard let first = rows.first?.count else { return true }
        return rows.allSatisfy { $0.count == first }
    }
}

// MARK: - パレット

/// ドットの役割 → 実際の色。スキンで体とウェアの色が変わる。
struct PixelPalette {
    var outline: Color
    var skin: Color
    var skinShade: Color
    var hair: Color
    var hairShade: Color
    var wear: Color
    var wearShade: Color
    var pants: Color
    var pantsShade: Color
    var eye: Color
    var light: Color
    var cheek: Color
    var metal: Color
    var dark: Color
    var wood: Color
    var leaf: Color
    /// 差し色。装備を描く直前に、そのレア度の色へ差し替える。
    var accent: Color = .white

    func color(for ink: PixelSprite.Ink) -> Color? {
        switch ink {
        case .none: return nil
        case .accent: return accent
        case .outline: return outline
        case .skin: return skin
        case .skinShade: return skinShade
        case .hair: return hair
        case .hairShade: return hairShade
        case .wear: return wear
        case .wearShade: return wearShade
        case .pants: return pants
        case .pantsShade: return pantsShade
        case .eye: return eye
        case .light: return light
        case .cheek: return cheek
        case .metal: return metal
        case .dark: return dark
        case .wood: return wood
        case .leaf: return leaf
        }
    }

    /// 影を作るときに混ぜる色（＝輪郭色）。色数を増やさず 1 色から陰影を作る。
    private static let ink = Color(hexF: 0x2A2320)
    private static let paper = Color(hexF: 0xFFFFFF)

    /// スキンからパレットを作る。
    ///
    /// スキンの差し色はどれも暗い（`SkinCatalog`）。そのままウェアに使うと輪郭と同化して
    /// キャラが黒い塊に見えるので、**ウェアは差し色を持ち上げ、ショートパンツは差し色そのまま**にして
    /// 上下を必ず分ける。髪は差し色のまま使う（暗いほうが髪らしい）。
    static func make(skin: CharacterSkin) -> PixelPalette {
        let body = Color(hexF: skin.bodyHex)
        let accent = Color(hexF: skin.accentHex)
        let bodyShade: Color = body.mix(with: ink, by: 0.26)
        let hairShade: Color = accent.mix(with: ink, by: 0.40)
        let wear: Color = accent.mix(with: paper, by: 0.30)
        let wearShade: Color = accent.mix(with: paper, by: 0.12)
        let pants: Color = accent.mix(with: paper, by: 0.06)
        let pantsShade: Color = accent.mix(with: ink, by: 0.22)
        return PixelPalette(
            // 輪郭は真っ黒にせず、少し茶を含ませる（ドット絵が硬くなりすぎないように）。
            outline: ink,
            skin: body,
            skinShade: bodyShade,
            hair: accent,
            hairShade: hairShade,
            wear: wear,
            wearShade: wearShade,
            pants: pants,
            pantsShade: pantsShade,
            eye: Color(hexF: 0x241F1C),
            light: Color(hexF: 0xFFFFFF),
            cheek: Color(hexF: 0xFF8A8A),
            metal: Color(hexF: 0xB9C0C9),
            dark: Color(hexF: 0x3A3330),
            wood: Color(hexF: 0xA9865F),
            leaf: Color(hexF: 0x4F8B3B)
        )
    }
}

extension Color {
    /// 2 色を混ぜる。ドット絵の影色を 1 色から作るために使う。
    func mix(with other: Color, by amount: Double) -> Color {
        let t = min(1, max(0, amount))
        let a = UIColor(self).rgba
        let b = UIColor(other).rgba
        return Color(
            red: a.r + (b.r - a.r) * t,
            green: a.g + (b.g - a.g) * t,
            blue: a.b + (b.b - a.b) * t
        )
    }
}

extension UIColor {
    fileprivate var rgba: (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
}

// MARK: - 描画

extension GraphicsContext {

    /// スプライトを描く。`origin` は左上、`dot` は 1 ドットの一辺（pt）。
    ///
    /// ドットの境目に隙間が出ないよう、矩形は必ず `dot` の整数倍の位置に置き、
    /// 幅も `dot` 単位で切り出す（小数座標にするとアンチエイリアスで滲んでドット絵に見えなくなる）。
    func drawPixels(
        _ sprite: PixelSprite,
        at origin: CGPoint,
        dot: CGFloat,
        palette: PixelPalette,
        flipped: Bool = false,
        opacity: Double = 1
    ) {
        guard dot > 0, sprite.width > 0 else { return }
        for run in sprite.runs {
            guard let color = palette.color(for: run.ink) else { continue }
            // 左右反転は「区間の開始位置を右端から測り直す」だけで済む。
            let x = flipped ? sprite.width - run.x - run.length : run.x
            let rect = CGRect(
                x: origin.x + CGFloat(x) * dot,
                y: origin.y + CGFloat(run.y) * dot,
                width: CGFloat(run.length) * dot,
                height: dot
            )
            fill(Path(rect), with: .color(opacity < 1 ? color.opacity(opacity) : color))
        }
    }
}
