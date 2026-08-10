import Foundation

/// 髪型とアクセサリーのドット絵（14 × 13・頭と同じ画枠）。
///
/// もともと髪は頭のスプライトに焼き込まれていたが、着せ替えできるように**層を分けた**。
/// `headBase`（髪の無い素体）→ 髪 → アクセサリー の順に重ねる。
/// 素体と現行の髪（`.short`）は、焼き込み版から機械的に切り出したので既存の見た目と 1 ドットも変わらない。
enum PixelHairArt {

    // MARK: - 素体（髪の無い頭）

    static func headBase(facing: CharacterScene.Facing, blinking: Bool) -> PixelSprite {
        switch facing {
        case .up: return headBaseBack
        case .left, .right: return blinking ? headBaseSideBlink : headBaseSide
        case .down: return blinking ? headBaseFrontBlink : headBaseFront
        }
    }

    static let headBaseFront = PixelSprite([
        "....oooooo....",
        "..oossssssoo..",
        ".osssssssssso.",
        "osssssssssssSo",
        "osssssssssssSo",
        "ossssssssssSSo",
        "osssssssssssSo",
        "ossslesslessSo",
        "ossseesseessSo",
        "osscsssssscsSo",
        "osssssoossssSo",
        "..osssssssso..",
        "...oooooooo...",
    ])

    static let headBaseFrontBlink = PixelSprite([
        "....oooooo....",
        "..oossssssoo..",
        ".osssssssssso.",
        "osssssssssssSo",
        "osssssssssssSo",
        "ossssssssssSSo",
        "osssssssssssSo",
        "osssssssssssSo",
        "osssoossoossSo",
        "osscsssssscsSo",
        "osssssoossssSo",
        "..osssssssso..",
        "...oooooooo...",
    ])

    static let headBaseBack = PixelSprite([
        "....oooooo....",
        "..oossssssoo..",
        ".osssssssssso.",
        "osssssssssssso",
        "ossssSSsssssso",
        "ossssSsSssssso",
        "osssssSSssssso",
        "osssssssssssso",
        "osssssssssssso",
        "osssssssssssso",
        "osssssssssssso",
        "..osssssssso..",
        "...oooooooo...",
    ])

    static let headBaseSide = PixelSprite([
        "...oooooo.....",
        ".oossssssoo...",
        "osssssssssso..",
        "ossssssssssso.",
        "osssssssssssso",
        "osssssssssssso",
        "osssssssseesso",
        "osssssssseesso",
        "osssssssscssso",
        "osssssssssooso",
        ".osssssssssso.",
        "..osssssssso..",
        "...oooooooo...",
    ])

    static let headBaseSideBlink = PixelSprite([
        "...oooooo.....",
        ".oossssssoo...",
        "osssssssssso..",
        "ossssssssssso.",
        "osssssssssssso",
        "osssssssssssso",
        "osssssssssssso",
        "ossssssssoosso",
        "osssssssscssso",
        "osssssssssooso",
        ".osssssssssso.",
        "..osssssssso..",
        "...oooooooo...",
    ])

    // MARK: - 髪型

    /// 髪型のカタログ。強さには一切関係しない見た目だけの要素。
    struct Style: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        /// 有料かどうか（無料の髪型は最初から所持）。
        let isPaid: Bool
        let priceLabel: String
    }

    static let defaultStyleId = "short"

    static let styles: [Style] = [
        Style(id: "short", name: "ショート", isPaid: false, priceLabel: "所持済み"),
        Style(id: "buzz", name: "ベリーショート", isPaid: false, priceLabel: "所持済み"),
        Style(id: "ponytail", name: "ポニーテール", isPaid: true, priceLabel: "¥250"),
        Style(id: "long", name: "ロング", isPaid: true, priceLabel: "¥250"),
    ]

    static func style(id: String?) -> Style {
        styles.first { $0.id == id } ?? styles[0]
    }

    static func isOwned(_ style: Style, purchased: Set<String>) -> Bool {
        !style.isPaid || purchased.contains(style.id)
    }

    /// 髪のスプライト。向きごとに絵を変える（背面は髪しか見えないので情報量がいちばん多い）。
    static func hair(styleId: String?, facing: CharacterScene.Facing) -> PixelSprite {
        let id = style(id: styleId).id
        switch (id, facing) {
        case ("buzz", .up): return buzzBack
        case ("buzz", .left), ("buzz", .right): return buzzSide
        case ("buzz", _): return buzzFront
        case ("ponytail", .up): return ponytailBack
        case ("ponytail", .left), ("ponytail", .right): return ponytailSide
        case ("ponytail", _): return ponytailFront
        case ("long", .up): return longBack
        case ("long", .left), ("long", .right): return longSide
        case ("long", _): return longFront
        case (_, .up): return shortBack
        case (_, .left), (_, .right): return shortSide
        default: return shortFront
        }
    }

    // MARK: ショート（従来の髪型。焼き込み版から切り出したので見た目は不変）

    private static let shortFront = PixelSprite([
        "..............",
        "....hhhhhh....",
        "..hhhhhhhhhh..",
        ".hhhhhhhhhhhH.",
        ".hhhhhhhhhhhH.",
        ".hh........HH.",
        ".h..........H.",
        ".h..........H.",
        ".h..........H.",
        ".h..........H.",
        ".h..........H.",
        "..............",
        "..............",
    ])

    private static let shortBack = PixelSprite([
        "..............",
        "....hhhhhh....",
        "..hhhhhhhhhh..",
        ".hhhhhhhhhhhh.",
        ".hhhhHHhhhhhh.",
        ".hhhhHhHhhhhh.",
        ".hhhhhHHhhhhh.",
        ".hhhhhhhhhhhh.",
        ".hhhhhhhhhhhh.",
        ".hhhhhhhhhhhh.",
        ".hhhhhhhhhhhh.",
        "...hhhhhhhh...",
        "..............",
    ])

    private static let shortSide = PixelSprite([
        "..............",
        "...hhhhhh.....",
        ".hhhhhhhhhh...",
        ".hhhhhhhhhhh..",
        ".hhhhhhhhh....",
        ".hhhhhhh......",
        ".hhhhhh.......",
        ".hhhhhh.......",
        ".hhhhhh.......",
        ".hhhhhh.......",
        "..hhhhh.......",
        "...hhh........",
        "..............",
    ])

    // MARK: ベリーショート（刈り上げ。横の毛が無い）

    private static let buzzFront = PixelSprite([
        "..............",
        "....hhhhhh....",
        "..hhhhhhhhhh..",
        ".hhhhhhhhhhhH.",
        "..hhhhhhhhhH..",
        "...........H..",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
    ])

    private static let buzzBack = PixelSprite([
        "..............",
        "....hhhhhh....",
        "..hhhhhhhhhh..",
        ".hhhhhhhhhhhh.",
        ".hhhhHHhhhhhh.",
        ".hhhhHhHhhhhh.",
        "..hhhhHHhhhh..",
        "...hhhhhhhh...",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
    ])

    private static let buzzSide = PixelSprite([
        "..............",
        "...hhhhhh.....",
        ".hhhhhhhhhh...",
        ".hhhhhhhhhhh..",
        "..hhhhhhh.....",
        "...hhhh.......",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
    ])

    // MARK: ポニーテール（後ろで束ねる。横と背面に尾が出る）

    private static let ponytailFront = PixelSprite([
        "..............",
        "....hhhhhh....",
        "..hhhhhhhhhh..",
        ".hhhhhhhhhhhH.",
        ".hhhhhhhhhhhH.",
        ".hh........HH.",
        ".h..........H.",
        ".h..........H.",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
    ])

    private static let ponytailBack = PixelSprite([
        "..............",
        "....hhhhhh....",
        "..hhhhhhhhhh..",
        ".hhhhhhhhhhhh.",
        ".hhhhhhhhhhhh.",
        ".hhhhhHHhhhhh.",
        ".hhhhhhHhhhhh.",
        ".hhhhhhHhhhhh.",
        "...hhhhHhhhh..",
        "......hHh.....",
        "......hHh.....",
        ".....hhHhh....",
        "......hhh.....",
    ])

    private static let ponytailSide = PixelSprite([
        "..............",
        "...hhhhhh.....",
        ".hhhhhhhhhh...",
        "hhhhhhhhhhh...",
        "hhhhhhhhh.....",
        "hHhhhhh.......",
        "hHhhhh........",
        "hHhhhh........",
        "hHhhh.........",
        "hHh...........",
        ".h............",
        "..............",
        "..............",
    ])

    // MARK: ロング（肩まで伸びる）

    private static let longFront = PixelSprite([
        "..............",
        "....hhhhhh....",
        "..hhhhhhhhhh..",
        ".hhhhhhhhhhhH.",
        ".hhhhhhhhhhhH.",
        ".hh........HH.",
        "hh..........HH",
        "hh..........HH",
        "hh..........HH",
        "hh..........HH",
        "hh..........HH",
        "hh..........HH",
        "hh..........HH",
    ])

    private static let longBack = PixelSprite([
        "..............",
        "....hhhhhh....",
        "..hhhhhhhhhh..",
        ".hhhhhhhhhhhh.",
        ".hhhhHHhhhhhh.",
        ".hhhhHhHhhhhh.",
        "hhhhhhHHhhhhhh",
        "hhhhhhhhhhhhhh",
        "hhhhhhhhhhhhhh",
        "hhhhhhhhhhhhhh",
        "hhhhhhhhhhhhhh",
        "hhhhhhhhhhhhhh",
        ".hhhhhhhhhhhh.",
    ])

    private static let longSide = PixelSprite([
        "..............",
        "...hhhhhh.....",
        ".hhhhhhhhhh...",
        "hhhhhhhhhhh...",
        "hhhhhhhhh.....",
        "hhhhhhh.......",
        "hhhhhh........",
        "hhhhhh........",
        "hhhhhh........",
        "hhhhhh........",
        "hhhhhh........",
        "hhhhhh........",
        "hhhhh.........",
    ])

    // MARK: - アクセサリー

    /// アクセサリー。遠征の戦利品（頭・手・腰・オーラ）とは別枠で、こちらは着せ替え用。
    struct Accessory: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let isPaid: Bool
        let priceLabel: String
    }

    static let accessories: [Accessory] = [
        Accessory(id: "none", name: "なし", isPaid: false, priceLabel: "所持済み"),
        Accessory(id: "glasses", name: "メガネ", isPaid: false, priceLabel: "所持済み"),
        Accessory(id: "shades", name: "サングラス", isPaid: true, priceLabel: "¥250"),
        Accessory(id: "earphones", name: "イヤホン", isPaid: true, priceLabel: "¥250"),
    ]

    static func accessory(id: String?) -> Accessory {
        accessories.first { $0.id == id } ?? accessories[0]
    }

    static func isOwned(_ accessory: Accessory, purchased: Set<String>) -> Bool {
        !accessory.isPaid || purchased.contains(accessory.id)
    }

    /// アクセサリーのスプライト。**背面では顔まわりの物を描かない**（後ろからメガネは見えない）。
    static func accessorySprite(id: String?, facing: CharacterScene.Facing) -> PixelSprite? {
        switch (accessory(id: id).id, facing) {
        case ("glasses", .up), ("shades", .up): return nil
        case ("glasses", .left), ("glasses", .right): return glassesSide
        case ("glasses", _): return glassesFront
        case ("shades", .left), ("shades", .right): return shadesSide
        case ("shades", _): return shadesFront
        case ("earphones", .up): return earphonesBack
        case ("earphones", .left), ("earphones", .right): return earphonesSide
        case ("earphones", _): return earphonesFront
        default: return nil
        }
    }

    private static let glassesFront = PixelSprite([
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        ".ooooo..ooooo.",
        ".obbbooobbbdo.",
        ".ooooo..ooooo.",
        "..............",
        "..............",
        "..............",
    ])

    private static let glassesSide = PixelSprite([
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..oooooooooo..",
        "..dddddobbbo..",
        "........ooooo.",
        "..............",
        "..............",
        "..............",
        "..............",
    ])

    private static let shadesFront = PixelSprite([
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        ".ooooooooooooo",
        ".odddoooddddo.",
        ".oddddooddddo.",
        "..ooo....ooo..",
        "..............",
        "..............",
    ])

    private static let shadesSide = PixelSprite([
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..oooooooooo..",
        "..ddddddddddo.",
        "........dddo..",
        "..............",
        "..............",
        "..............",
        "..............",
    ])

    private static let earphonesFront = PixelSprite([
        "..............",
        "....oooooo....",
        "..oo......oo..",
        ".o..........o.",
        "od..........do",
        "od..........do",
        "od..........do",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
    ])

    private static let earphonesBack = PixelSprite([
        "..............",
        "....oooooo....",
        "..oo......oo..",
        ".o..........o.",
        "od..........do",
        "od..........do",
        "od..........do",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
    ])

    private static let earphonesSide = PixelSprite([
        "..............",
        "...oooooo.....",
        ".oo......o....",
        "o.............",
        "o....dd.......",
        "o....dd.......",
        "o....dd.......",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
    ])
}
