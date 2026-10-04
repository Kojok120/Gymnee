import SwiftUI

/// 週ボスのドット絵（issue #128）。
///
/// 画枠は **16 x 16**（ペットと同じ）。体色は `Ink.accent` / `Ink.accentShade` に寄せてあり、
/// `palette(bossId:)` の差し替えだけでボスごとの色が変わる（`PixelPetArt` と同じ手）。
///
/// **絵を足したら `PixelArtGallery` と `PixelCharacterTests.allSprites` にも足すこと。**
enum PixelBossArt {

    static let canvasWidth = 16
    static let canvasHeight = 16

    /// サボリスライム。
    static let slime = PixelSprite([
        "................",
        "................",
        "................",
        ".......oo.......",
        "......orro......",
        "....oorrrroo....",
        "...orrrrrrrro...",
        "..orlrrrrrrrro..",
        "..orllrrrrrrro..",
        ".orrrrrrrrrrrro.",
        ".orrddrrrrddrro.",
        ".orrrrrrrrrrrro.",
        ".orrrrrddrrrrro.",
        ".oRrrrrrrrrrrRo.",
        "..oRRRRRRRRRRo..",
        "...oooooooooo...",
    ])

    /// ソファゴーレム。
    static let couchGolem = PixelSprite([
        "................",
        "................",
        "...oooooooooo...",
        "..orrrrrrrrrro..",
        "..orlerrrrlero..",
        "..orrrrrrrrrro..",
        "..orrrddddrrro..",
        "ooooRRRRRRRRoooo",
        "orrofffffffforro",
        "orrofffffffforro",
        "orrRRRRRRRRRRrro",
        "oRRRRRRRRRRRRRRo",
        "okkooooooooookko",
        "okko........okko",
        "oooo........oooo",
        "................",
    ])

    /// ネボウドラゴン。
    static let snoozeDragon = PixelSprite([
        "................",
        "..oo........oo..",
        "..oRo......oRo..",
        "...oRo....oRo...",
        "...oorrrrrroo...",
        "..orrrrrrrrrro..",
        ".orrddrrrrddrro.",
        ".orrrrrrrrrrrro.",
        ".orrrrrrrrrrrro.",
        ".oRrrrllllrrrRo.",
        "..oRrlddddlrRo..",
        "...oRlllllllo...",
        "..orRRRRRRRRro..",
        ".orroRRRRRRorro.",
        ".oRo.oRRRRo.oRo.",
        "..o...oooo...o..",
    ])

    /// ジャンククラーケン。
    static let junkKraken = PixelSprite([
        "................",
        ".....oooooo.....",
        "....orrrrrro....",
        "...orrrrrrrro...",
        "..orrrrrrrrrro..",
        "..orrrrrrrrrro..",
        "..orrlerrlerro..",
        "..orrrrrrrrrro..",
        "..orrrrddrrrro..",
        "...oRrrrrrrRo...",
        "..orRorrrroRro..",
        ".orRo.orro.oRro.",
        ".oRo.orRRro.oRo.",
        "orRo.oRooRo.oRro",
        "oRo..oo..oo..oRo",
        ".o............o.",
    ])

    /// ボスの絵。知らない id はスライムにする（サーバーが先にボスを増やしても落ちない）。
    static func sprite(bossId: String) -> PixelSprite {
        switch bossId {
        case "couch_golem": return couchGolem
        case "snooze_dragon": return snoozeDragon
        case "junk_kraken": return junkKraken
        default: return slime
        }
    }

    /// ボスごとの配色。体色（accent）とそのかげ（accentShade）だけを差し替える。
    static func palette(bossId: String) -> PixelPalette {
        var palette = PixelPalette.neutral
        let colors: (UInt, UInt)
        switch bossId {
        case "couch_golem": colors = (0xB5654A, 0x7E4130)
        case "snooze_dragon": colors = (0x7E6BD6, 0x5546A3)
        case "junk_kraken": colors = (0xE0708A, 0xA94A60)
        default: colors = (0x8BC34A, 0x5E8F2E)
        }
        palette.accent = Color(hexF: colors.0)
        palette.accentShade = Color(hexF: colors.1)
        return palette
    }
}
