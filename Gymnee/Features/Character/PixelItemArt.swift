import Foundation
import SwiftUI

/// 装備・戦利品・遠征コースのドット絵（16 × 16）。
///
/// SF Symbol を使わない理由は画風の統一。ベクターのシンボルは曲線が滑らかに出るため、
/// ドット格子に吸着させたキャラや部屋と同じ画面に置くと、そこだけ質感が浮いて安っぽく見える。
/// 外部のアイコン集（game-icons.net など）も同じ理由で混ぜていない。
///
/// 差し色（`r` / `R`）はレア度の色に置き換わるので、1 枚の絵で 3 段階のレア度を表せる。
enum PixelItemArt {

    static let side = 16

    // MARK: - 戦利品アイコン

    /// 戦利品 12 種のアイコン。id は `Expedition.items` に対応する。
    static func icon(for item: Expedition.Item) -> PixelSprite {
        switch item.id {
        case "sweat-band": return headband
        case "cap": return cap
        case "crown": return crown
        case "wristband": return wristband
        case "power-grip": return powerGrip
        case "golden-grip": return goldenGrip
        case "cloth-belt": return clothBelt
        case "lifting-belt": return liftingBelt
        case "champion-belt": return championBelt
        case "protein-aura": return proteinAura
        case "sweat-aura": return steamAura
        case "legend-aura": return legendAura
        default: return unknown
        }
    }

    // MARK: 頭

    private static let headband = PixelSprite([
        "................",
        "................",
        "................",
        "................",
        "...oooooooooo...",
        "..oRRRRRRRRRRo..",
        "..oRrrrrrrrrRo..",
        "..oRrrrrrrrrRo..",
        "..oRRRRRRRRRRo..",
        "...oooooooooo...",
        "..........oo....",
        ".........oRRo...",
        "........oRrrRo..",
        ".........oRRo...",
        "..........oo....",
        "................",
    ])

    private static let cap = PixelSprite([
        "................",
        "................",
        ".....oooooo.....",
        "...ooRRRRRRoo...",
        "..oRRrrrrrrRRo..",
        "..oRrrrrrrrrRo..",
        ".oRrrrrrrrrrrRo.",
        ".oRrrrrrrrrrrRo.",
        ".oRRrrrrrrrrRRo.",
        ".oooRRRRRRRRooo.",
        "...ooooooooooooo",
        "...ollllllllllo.",
        "....oooooooooo..",
        "................",
        "................",
        "................",
    ])

    private static let crown = PixelSprite([
        "................",
        "................",
        "..o..........o..",
        ".olo...oo...olo.",
        ".oro..olro..oro.",
        ".oro.oorroo.oro.",
        ".oro.orrrro.oro.",
        ".orroorrrroorro.",
        ".orrrrrrrrrrrro.",
        ".oRrrRrrrrRrrRo.",
        ".oRRRRRRRRRRRRo.",
        ".oRlRRlRRlRRlRo.",
        ".oRRRRRRRRRRRRo.",
        "..oooooooooooo..",
        "................",
        "................",
    ])

    // MARK: 手

    private static let wristband = PixelSprite([
        "................",
        "................",
        "................",
        "....oooooooo....",
        "...oRRRRRRRRo...",
        "..oRrrrrrrrrRo..",
        "..oRrrrrrrrrRo..",
        "..oRrrllrrrrRo..",
        "..oRrrllrrrrRo..",
        "..oRrrrrrrrrRo..",
        "..oRrrrrrrrrRo..",
        "...oRRRRRRRRo...",
        "....oooooooo....",
        "................",
        "................",
        "................",
    ])

    private static let powerGrip = PixelSprite([
        "................",
        "................",
        "...oooo..oooo...",
        "..oRrrRooRrrRo..",
        "..oRrrrrrrrrRo..",
        "..oRrrrrrrrrRo..",
        "..oRRrrrrrrRRo..",
        "...oRRRRRRRRo...",
        "....oRRRRRRo....",
        "....ommmmmmo....",
        "....ommmmmmo....",
        "....oddddddo....",
        ".....oooooo.....",
        "................",
        "................",
        "................",
    ])

    private static let goldenGrip = PixelSprite([
        "................",
        "......oooo......",
        "....ooRrrRoo....",
        "...oRrrllrrRo...",
        "..oRrrlllrrrRo..",
        "..oRrrrllrrrRo..",
        "..oRrrrrrrrrRo..",
        "..oRRrrrrrrRRo..",
        "...oRRRRRRRRo...",
        "...ommmmmmmmo...",
        "...ommllmmmmo...",
        "...ommmmmmmmo...",
        "...odddddddddo..",
        "....oooooooooo..",
        "................",
        "................",
    ])

    // MARK: 腰

    private static let clothBelt = PixelSprite([
        "................",
        "................",
        "................",
        "................",
        "..oooooooooooo..",
        ".oRRRRRRRRRRRRo.",
        ".oRrrrrrrrrrrRo.",
        ".oRrroooooorrRo.",
        ".oRrrommmmorrRo.",
        ".oRrroooooorrRo.",
        ".oRrrrrrrrrrrRo.",
        ".oRRRRRRRRRRRRo.",
        "..oooooooooooo..",
        "................",
        "................",
        "................",
    ])

    private static let liftingBelt = PixelSprite([
        "................",
        "................",
        "................",
        ".oooooooooooooo.",
        ".oRRRRRRRRRRRRo.",
        ".oRrrrrrrrrrrRo.",
        "oooooooooooooooo",
        "ommmoRrrrRommmmo",
        "ommmoRrrrRommmmo",
        "oooooooooooooooo",
        ".oRrrrrrrrrrrRo.",
        ".oRRRRRRRRRRRRo.",
        ".oooooooooooooo.",
        "................",
        "................",
        "................",
    ])

    private static let championBelt = PixelSprite([
        "................",
        "................",
        ".oooooooooooooo.",
        ".oRRRRRRRRRRRRo.",
        ".oRrrrrrrrrrrRo.",
        "ooooooooooooooo.",
        "ommoooooooooomo.",
        "ommommllmmmommo.",
        "ommommmmmlmommo.",
        "ommoooooooooomo.",
        "ooooooooooooooo.",
        ".oRrrrrrrrrrrRo.",
        ".oRRRRRRRRRRRRo.",
        ".oooooooooooooo.",
        "................",
        "................",
    ])

    // MARK: オーラ

    /// プロテインの香り。葉と鉢で描くと観葉植物に見えるので、
    /// シェイカーから香りが立ちのぼる形にする（同じオーラ枠の「湯気」とも造形を揃える）。
    private static let proteinAura = PixelSprite([
        "................",
        "....r...r...r...",
        "...r...r...r....",
        "....r...r...r...",
        "...r...r...r....",
        "................",
        "....oooooooo....",
        "...oRRRRRRRRo...",
        "..oooooooooooo..",
        "..orrrrrrrrrro..",
        "..orrrrrrrrrro..",
        "..oRRRRRRRRRRo..",
        "..orrrrrrrrrro..",
        "..orrrrrrrrrro..",
        "..orrrrrrrrrro..",
        "..oooooooooooo..",
    ])

    private static let steamAura = PixelSprite([
        "................",
        "...o......o.....",
        "..oro....oro....",
        "..oro...oro.....",
        "...oro..oro.....",
        "...oro...oro....",
        "..oro.....oro...",
        "..oro....oro....",
        "...oro...oro....",
        "....o.....o.....",
        "................",
        "..oooooooooooo..",
        ".oRRRRRRRRRRRRo.",
        ".oRRRRRRRRRRRRo.",
        "..oooooooooooo..",
        "................",
    ])

    private static let legendAura = PixelSprite([
        "................",
        ".......oo.......",
        "......orro......",
        "......orro......",
        "..o...orro...o..",
        ".olo..orro..olo.",
        "..o..oorroo..o..",
        ".ooooorrrrooooo.",
        ".orrrrrllrrrrro.",
        ".ooooorrrrooooo.",
        "..o..oorroo..o..",
        ".olo..orro..olo.",
        "..o...orro...o..",
        "......orro......",
        "......orro......",
        ".......oo.......",
    ])

    private static let unknown = PixelSprite([
        "................",
        "................",
        "................",
        "....oooooooo....",
        "...oRRRRRRRRo...",
        "..oRrrrrrrrrRo..",
        "..oRrrrrrrrrRo..",
        "..oRrrrrrrrrRo..",
        "..oRrrrrrrrrRo..",
        "..oRrrrrrrrrRo..",
        "..oRrrrrrrrrRo..",
        "...oRRRRRRRRo...",
        "....oooooooo....",
        "................",
        "................",
        "................",
    ])

    // MARK: - 遠征コース

    /// 遠征コース 4 種の絵。
    static func course(id: String) -> PixelSprite {
        switch id {
        case "morning-hill": return morningHill
        case "iron-forest": return ironForest
        case "old-gym": return oldGym
        case "summit": return summit
        default: return morningHill
        }
    }

    private static let morningHill = PixelSprite([
        "bbbbbbbbbbbbbbbb",
        "bbbbbbbbbbbbbbbb",
        "bbbbbbblllbbbbbb",
        "bbbbbbllllbbbbbb",
        "bbbbbbllllbbbbbb",
        "bbbbbbbllbbbbbbb",
        "bbbbbbbbbbbbbbbb",
        "bbbbbbbbbbbbbbbb",
        "bbbbggggbbbbbbbb",
        "bbbgggggggbbbbbb",
        "bbggggggggggbbbb",
        "gggggggggggggggg",
        "gggggggggggggggg",
        "gggggggggggggggg",
        "kkkkkkkkkkkkkkkk",
        "kkkkkkkkkkkkkkkk",
    ])

    private static let ironForest = PixelSprite([
        "bbbbbbbbbbbbbbbb",
        "bbbbbbbggbbbbbbb",
        "bbbbbbggggbbbbbb",
        "bbbbbgggggbbbbbb",
        "bbbggggggggbbbbb",
        "bbggggggggggbbbb",
        "bbbbbggggbbbbbbb",
        "bbbggggggggbbbbb",
        "bbggggggggggbbbb",
        "bgggggggggggbbbb",
        "bbbbbbkkbbbbbbbb",
        "bbbbbbkkbbbbbbbb",
        "bbbbbbkkbbbbbbbb",
        "bbbbbbkkbbbbbbbb",
        "gggggggggggggggg",
        "kkkkkkkkkkkkkkkk",
    ])

    private static let oldGym = PixelSprite([
        "bbbbbbbbbbbbbbbb",
        "bbbbbbbbbbbbbbbb",
        "bbbooooooooobbbb",
        "bboddddddddobbbb",
        "bodddddddddobbbb",
        "boddbbddbbdobbbb",
        "boddbbddbbdobbbb",
        "bodddddddddobbbb",
        "boddbbddbbdobbbb",
        "boddbbddbbdobbbb",
        "bodddddddddobbbb",
        "boddddbbdddobbbb",
        "boddddbbdddobbbb",
        "bodddddddddobbbb",
        "oooooooooooooooo",
        "kkkkkkkkkkkkkkkk",
    ])

    private static let summit = PixelSprite([
        "bbbbbbbbbbbbbbbb",
        "bbbbbbbbbbbbbbbb",
        "bbbbbbbllbbbbbbb",
        "bbbbbbllllbbbbbb",
        "bbbbbolllllbbbbb",
        "bbbbbomlllobbbbb",
        "bbbbommmmmobbbbb",
        "bbbommmmmmmobbbb",
        "bbommmmmmmmmobbb",
        "bommmmmmmmmmmobb",
        "ommmmmmmmmmmmmob",
        "ommmmmmmmmmmmmmo",
        "oooooooooooooooo",
        "gggggggggggggggg",
        "kkkkkkkkkkkkkkkk",
        "kkkkkkkkkkkkkkkk",
    ])
}

/// 部屋に落ちているグッズのドット絵（12 × 12）。
///
/// 戦利品（16 × 12 の装備）より一回り小さい。床に転がっている物なので、
/// キャラより目立つと部屋の主役が入れ替わってしまう。
extension PixelItemArt {

    static let pickupSide = 12

    /// グッズごとの配色。**レア度の色を流用しない**。
    /// 装備は「レア度が価値」だが、こちらは食べ物・飲み物なので、
    /// 色がその物を表していないと何が落ちているのか読めない（バナナが灰色の棒になる）。
    static func pickupPalette(id: String) -> PixelPalette {
        var palette = PixelPalette.neutral
        switch id {
        case "coffee":
            palette.accent = Color(hexF: 0xC9C6C0)      // 湯気
            palette.cloth = Color(hexF: 0x7A4A2B)       // 中身のコーヒー
        case "banana":
            palette.accent = Color(hexF: 0xF7D046)
            palette.dark = Color(hexF: 0x8A6B1F)
        case "amino":
            palette.accent = Color(hexF: 0x4FC1E9)
        case "protein-bar":
            palette.accent = Color(hexF: 0x9A6234)
        case "creatine":
            palette.accent = Color(hexF: 0xE8563F)
        default:
            break
        }
        return palette
    }

    static func pickup(id: String) -> PixelSprite {
        switch id {
        case "coffee": return coffee
        case "banana": return banana
        case "amino": return aminoBottle
        case "protein-bar": return proteinBar
        case "creatine": return creatineTub
        default: return coffee
        }
    }

    /// コーヒー。湯気付きの紙カップ。
    private static let coffee = PixelSprite([
        "............",
        "..r......r..",
        "...r....r...",
        "..r......r..",
        "............",
        "..oooooooo..",
        "..ollllllo..",
        "..offffffo..",
        "..offffffo..",
        "...offffo...",
        "...oooooo...",
        "............",
    ])

    /// バナナ。
    private static let banana = PixelSprite([
        "............",
        ".......dd...",
        "......drrd..",
        ".....drrrd..",
        "....drrrd...",
        "...drrrd....",
        "..drrrd.....",
        "..drrd......",
        "..ddd.......",
        "............",
        "............",
        "............",
    ])

    /// アミノ酸サプリ。ボトル。
    private static let aminoBottle = PixelSprite([
        "............",
        "....oooo....",
        "....ommo....",
        "...oooooo...",
        "..orrrrrro..",
        "..orrrrrro..",
        "..ollllllo..",
        "..orrrrrro..",
        "..orrrrrro..",
        "..orrrrrro..",
        "...oooooo...",
        "............",
    ])

    /// プロテインバー。包装のねじりを両端に。
    private static let proteinBar = PixelSprite([
        "............",
        "............",
        "............",
        ".o........o.",
        "oooooooooooo",
        "orrllrrrrrro",
        "orrrrrrrrrro",
        "orrrrrrllrro",
        "oooooooooooo",
        ".o........o.",
        "............",
        "............",
    ])

    /// クレアチンサプリ。大きめのタブ（レアなので一回り大きく見せる）。
    private static let creatineTub = PixelSprite([
        "............",
        "...oooooo...",
        "...ommmmo...",
        "..oooooooo..",
        "..orrrrrro..",
        "..orllllro..",
        "..orlddlro..",
        "..orllllro..",
        "..orrrrrro..",
        "..orrrrrro..",
        "..oooooooo..",
        "............",
    ])
}
