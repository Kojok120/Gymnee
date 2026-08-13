import SwiftUI

/// ペットのドット絵。
///
/// 画枠は **16 x 16**（キャラの 24 x 24 の半分）。同じ `dot` で描くだけで「小さい生き物」に見える。
/// 足元は最下段に接するので、キャラと同じ「足元アンカー」でそのまま置ける。
///
/// 体色は `Ink.accent` / `Ink.accentShade` に寄せてあり、`palette(petId:)` の差し替えだけで
/// 種類ごとの色が変わる（`PixelItemArt.pickupPalette(id:)` と同じ手）。使う Ink は
/// outline / accent / accentShade / light / eye / dark の 6 つだけに絞る。
///
/// 耳は頭の上に **2 段だけ**乗せる。3 段にすると頭の上辺が深く切れ込んで、
/// 耳ではなく角が生えているように見える（実際にそうなって描き直した）。
///
/// **絵を足したら `PixelArtGallery` の `.pets` と `PixelCharacterTests.allSprites` にも足すこと。**
enum PixelPetArt {

    static let canvasWidth = 16
    static let canvasHeight = 16

    /// しばいぬ・正面。
    static let shibaFront = PixelSprite([
        "................",
        "................",
        "................",
        "...oo......oo...",
        "..oRro....orRo..",
        "..orrroooorrro..",
        ".orrrrrrrrrrrro.",
        ".orrerrrrrrerro.",
        ".orrrrrrrrrrrro.",
        ".orrrrrddrrrrro.",
        "..orrrrddrrrro..",
        "...oorrrrrroo...",
        "..oollllllloo...",
        "..olllllllllo...",
        "..olllllllllo...",
        "..oddoolloddo...",
    ])

    /// しばいぬ・正面（まばたき）。
    static let shibaFrontBlink = PixelSprite([
        "................",
        "................",
        "................",
        "...oo......oo...",
        "..oRro....orRo..",
        "..orrroooorrro..",
        ".orrrrrrrrrrrro.",
        ".orroorrrroorro.",
        ".orrrrrrrrrrrro.",
        ".orrrrrddrrrrro.",
        "..orrrrddrrrro..",
        "...oorrrrrroo...",
        "..oollllllloo...",
        "..olllllllllo...",
        "..olllllllllo...",
        "..oddoolloddo...",
    ])

    /// しばいぬ・横（右向き。左向きは反転して描く）。
    static let shibaSide = PixelSprite([
        "................",
        "................",
        "................",
        "..........oo....",
        ".........orrRo..",
        "........orrrrro.",
        "...oo...orrerrdo",
        "..orro..orrrrrdo",
        "..orroooorrrrro.",
        ".orrrrrrrrrrro..",
        ".orrrrrrrrrrro..",
        ".ollllllllllo...",
        ".oo.oo..oo.oo...",
        ".ol.ol..ol.ol...",
        ".ol.ol..ol.ol...",
        ".od.od..od.od...",
    ])

    /// しばいぬ・背面（尻尾が右に出る）。
    static let shibaBack = PixelSprite([
        "................",
        "................",
        "................",
        "...oo......oo...",
        "..oRro....orRo..",
        "..orrroooorrro..",
        ".orrrrrrrrrrrro.",
        ".orrrrrrrrrrrro.",
        ".orrrrrrrrrrrro.",
        ".orrrrrrrrrrrro.",
        "..orrrrrrrrrro..",
        "...oorrrrrrooo..",
        "..oollllllloRro.",
        "..olllllllllRo..",
        "..olllllllllo...",
        "..oddoolloddo...",
    ])

    /// とらねこ・正面。
    static let tabbyFront = PixelSprite([
        "................",
        "................",
        "...o........o...",
        "..oro......oro..",
        "..orro....orro..",
        "..orrroooorrro..",
        ".orrrrrrrrrrrro.",
        ".orrerrrrrrerro.",
        ".orrrrrrrrrrrro.",
        ".orrrrrddrrrrro.",
        "..orrrrddrrrro..",
        "...oorrrrrroo...",
        "..oollllllloo...",
        "..olllllllllo...",
        "..olllllllllo...",
        "..oddoolloddo...",
    ])

    /// とらねこ・正面（まばたき）。
    static let tabbyFrontBlink = PixelSprite([
        "................",
        "................",
        "...o........o...",
        "..oro......oro..",
        "..orro....orro..",
        "..orrroooorrro..",
        ".orrrrrrrrrrrro.",
        ".orroorrrroorro.",
        ".orrrrrrrrrrrro.",
        ".orrrrrddrrrrro.",
        "..orrrrddrrrro..",
        "...oorrrrrroo...",
        "..oollllllloo...",
        "..olllllllllo...",
        "..olllllllllo...",
        "..oddoolloddo...",
    ])

    /// とらねこ・横（右向き。左向きは反転して描く）。
    static let tabbySide = PixelSprite([
        "................",
        "................",
        "..........o.....",
        ".........oro....",
        "........orrro...",
        "...o....orrrrro.",
        "..oro...orrerrdo",
        "..oro...orrrrrdo",
        "..orooooorrrrro.",
        ".orrrrrrrrrrro..",
        ".orrrrrrrrrrro..",
        ".ollllllllllo...",
        ".oo.oo..oo.oo...",
        ".ol.ol..ol.ol...",
        ".ol.ol..ol.ol...",
        ".od.od..od.od...",
    ])

    /// とらねこ・背面（尻尾が右に立つ）。
    static let tabbyBack = PixelSprite([
        "................",
        "................",
        "...o........o...",
        "..oro......oro..",
        "..orro....orro..",
        "..orrroooorrro..",
        ".orrrrrrrrrrrro.",
        ".orrrrrrrrrrrro.",
        ".orrrrrrrrrrrro.",
        ".orrrrrrrrrrrro.",
        "..orrrrrrrrroo..",
        "...oorrrrrrorRo.",
        "..oollllllloRro.",
        "..ollllllllloro.",
        "..olllllllllo...",
        "..oddoolloddo...",
    ])

    /// 種類と向きから絵を選ぶ。左向きは横向きの絵を反転して描くので、ここでは右向きだけを返す。
    static func sprite(petId: String, facing: CharacterScene.Facing, blink: Bool) -> PixelSprite {
        switch (petId, facing) {
        case ("tabby", .up): return tabbyBack
        case ("tabby", .left), ("tabby", .right): return tabbySide
        case ("tabby", _): return blink ? tabbyFrontBlink : tabbyFront
        case (_, .up): return shibaBack
        case (_, .left), (_, .right): return shibaSide
        default: return blink ? shibaFrontBlink : shibaFront
        }
    }

    /// 種類ごとの配色。体色（accent）とそのかげ（accentShade）だけを差し替える。
    static func palette(petId: String) -> PixelPalette {
        var palette = PixelPalette.neutral
        switch petId {
        case "tabby":
            palette.accent = Color(hexF: 0x9AA3AD)
            palette.accentShade = Color(hexF: 0x6E767F)
        default:
            palette.accent = Color(hexF: 0xD9944B)
            palette.accentShade = Color(hexF: 0xA96A2E)
        }
        return palette
    }
}
