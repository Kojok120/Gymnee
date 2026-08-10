import Foundation

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
