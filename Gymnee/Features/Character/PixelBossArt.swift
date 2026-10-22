import SwiftUI

/// 週ボスのドット絵（issue #128。ランク別の見た目は #133）。
///
/// 画枠は **16 x 16**（ペットと同じ）。体色は `Ink.accent` / `Ink.accentShade` に寄せてあり、
/// `palette(bossId:)` の差し替えだけでボスごとの色が変わる（`PixelPetArt` と同じ手）。
///
/// **絵を足したら `PixelArtGallery` と `PixelCharacterTests.allSprites` にも足すこと。**
/// 季節のボス（issue #155）は帽子やもちを載せるので、`d` `f` `l` `c` の色もボスごとに差し替える。
enum PixelBossArt {

    static let canvasWidth = 16
    static let canvasHeight = 16

    /// サボリスライム。
    static let slimeRows = [
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
    ]
    static let slime = PixelSprite(slimeRows)

    /// ソファゴーレム。
    static let couchGolemRows = [
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
    ]
    static let couchGolem = PixelSprite(couchGolemRows)

    /// ネボウドラゴン。
    static let snoozeDragonRows = [
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
    ]
    static let snoozeDragon = PixelSprite(snoozeDragonRows)

    /// ジャンククラーケン。
    static let junkKrakenRows = [
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
    ]
    static let junkKraken = PixelSprite(junkKrakenRows)

    // MARK: - 季節のボス（issue #155）

    /// カボチャスライム（ハロウィン）。魔女の帽子は `d`、帽子の帯は `f`、光る顔は `l`。
    static let pumpkinSlimeRows = [
        "..........oo....",
        ".........odo....",
        "........oddo....",
        ".......odddo....",
        "......oddddo....",
        ".....offfffo....",
        ".oddddddddddddo.",
        ".orrRrrrrrRrrro.",
        "orrrRrrrrrRrrrro",
        "orrlllrrrrlllrro",
        "orrrlrRrrRrlrrro",
        "orrrrrRrrRrrrrro",
        "orrllllllllllrro",
        "oRrrllrRRrllrrRo",
        ".oRRRRRRRRRRRRo.",
        "..oooooooooooo..",
    ]
    static let pumpkinSlime = PixelSprite(pumpkinSlimeRows)

    /// サンタゴーレム（クリスマス）。ソファゴーレムにサンタ帽（`c` と `l`）を載せる。
    static let santaGolemRows = [
        "....oooooo......",
        "...occcccccoo...",
        "..occcccccccccoo",
        "..olllllllllloll",
        "..orrrrrrrrrrooo",
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
    ]
    static let santaGolem = PixelSprite(santaGolemRows)

    /// ネショウガツドラゴン（年末年始）。ネボウドラゴンの角のあいだに鏡もち（`l`）とみかん（`f`）。
    static let newYearDragonRows = [
        ".......oo.......",
        "..oo..offo..oo..",
        "..oRoollllooRo..",
        "...oRollllllRo..",
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
    ]
    static let newYearDragon = PixelSprite(newYearDragonRows)

    // MARK: - 練習用のかかし（issue #155）

    /// 記録画面の戦闘で、週ボスと戦わないときの相手。わら（`f`）と木（`k`）、赤い帯（`r`）。
    static let trainingDummy = PixelSprite([
        "................",
        ".....oooooo.....",
        "....offffffo....",
        "...offdffdffo...",
        "...offffffffo...",
        "...offfddfffo...",
        "....offffffo....",
        ".ooooookkoooooo.",
        "okkkkkokkokkkkko",
        ".oooooffffooooo.",
        ".....offffo.....",
        ".....orrrro.....",
        "......okko......",
        "......okko......",
        "....ookkkkoo....",
        "...oooooooooo...",
    ])

    static let trainingDummyPalette: PixelPalette = {
        var palette = PixelPalette.neutral
        palette.cloth = Color(hexF: 0xD9B86C)
        palette.accent = Color(hexF: 0xE8483F)
        palette.accentShade = Color(hexF: 0xB0302A)
        return palette
    }()

    /// ボスの絵。知らない id はスライムにする（サーバーが先にボスを増やしても落ちない）。
    static func sprite(bossId: String) -> PixelSprite {
        switch bossId {
        case "couch_golem": return couchGolem
        case "snooze_dragon": return snoozeDragon
        case "junk_kraken": return junkKraken
        case "pumpkin_slime": return pumpkinSlime
        case "santa_golem": return santaGolem
        case "newyear_dragon": return newYearDragon
        default: return slime
        }
    }

    // MARK: - ランク（issue #133）

    /// 強いランクの王冠。体の色と混ざらないよう、ボスの絵が使わない金属（`m`）で描く。
    static let crownRows = [
        "....o..oo..o....",
        "...omoommoomo...",
        "...ommmmmmmmo...",
        "...oooooooooo...",
    ]

    private static func rows(bossId: String) -> [String] {
        switch bossId {
        case "couch_golem": return couchGolemRows
        case "snooze_dragon": return snoozeDragonRows
        case "junk_kraken": return junkKrakenRows
        default: return slimeRows
        }
    }

    /// ランク込みの絵。強いランクは頭上の空き行を詰めて王冠を載せる（1枚の絵にしてドットの格子をずらさない）。
    /// 季節のボスは帽子をかぶっているので王冠を載せず、強さは配色とオーラだけで見せる。
    static func sprite(bossId: String, tier: PartyBoss.Tier) -> PixelSprite {
        guard tier == .strong, SeasonalEvent.event(bossId: bossId) == nil else { return sprite(bossId: bossId) }
        let body = rows(bossId: bossId).drop { !$0.contains(where: { $0 != "." }) }
        return PixelSprite(crownRows + Array(body))
    }

    /// ランク込みの配色。弱いは淡く、強いは暗い体に赤い目、金の王冠。
    static func palette(bossId: String, tier: PartyBoss.Tier) -> PixelPalette {
        var palette = palette(bossId: bossId)
        switch tier {
        case .weak:
            palette.accent = palette.accent.mix(with: .white, by: 0.4)
            palette.accentShade = palette.accentShade.mix(with: .white, by: 0.4)
        case .medium:
            break
        case .strong:
            palette.accent = palette.accent.mix(with: Color(hexF: 0x1A0F14), by: 0.35)
            palette.accentShade = palette.accentShade.mix(with: Color(hexF: 0x1A0F14), by: 0.45)
            palette.eye = Color(hexF: 0xFF3B30)
            palette.metal = Color(hexF: 0xF5C542)
        }
        return palette
    }

    /// ボスごとの配色。体色（accent）とそのかげ（accentShade）だけを差し替える。
    static func palette(bossId: String) -> PixelPalette {
        var palette = PixelPalette.neutral
        let colors: (UInt, UInt)
        switch bossId {
        case "couch_golem": colors = (0xB5654A, 0x7E4130)
        case "snooze_dragon": colors = (0x7E6BD6, 0x5546A3)
        case "junk_kraken": colors = (0xE0708A, 0xA94A60)
        case "pumpkin_slime":
            colors = (0xFF8A1E, 0xC85A0A)
            palette.dark = Color(hexF: 0x6A3D9A)
            palette.cloth = Color(hexF: 0xF5C542)
            palette.light = Color(hexF: 0xFFE066)
        case "santa_golem":
            colors = (0xB5654A, 0x7E4130)
            palette.cheek = Color(hexF: 0xE8483F)
        case "newyear_dragon":
            colors = (0x7E6BD6, 0x5546A3)
            palette.cloth = Color(hexF: 0xFF9F1C)
        default: colors = (0x8BC34A, 0x5E8F2E)
        }
        palette.accent = Color(hexF: colors.0)
        palette.accentShade = Color(hexF: colors.1)
        return palette
    }
}
