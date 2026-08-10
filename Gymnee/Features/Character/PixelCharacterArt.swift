import Foundation

/// キャラのドット絵。**絵そのものはここに全部ある**。
///
/// パーツ単位で持ち、合成は `PixelCharacterRenderer` が整数ドット単位で行う。
/// パーツに分けている理由は 2 つ:
/// - 体格（胴 3 種 × 腕 2 種 × 脚 2 種）を現実の記録で選び分けられる。1 枚絵だと 12 通り描く必要がある
/// - 装備を重ねられる。1 枚絵だと 体型 × 装備 の全組み合わせが要る
///
/// キャラの画枠は 24 × 24 ドット。足元が y=23、頭のてっぺんが y=0。
enum PixelCharacterArt {

    /// キャラ 1 体の画枠（ドット）。
    static let canvasWidth = 24
    static let canvasHeight = 24

    // MARK: - 頭（14 × 13）

    /// 通常の顔。
    static let head = PixelSprite([
        "....oooooo....",
        "..oohhhhhhoo..",
        ".ohhhhhhhhhho.",
        "ohhhhhhhhhhhHo",
        "ohhhhhhhhhhhHo",
        "ohhssssssssHHo",
        "ohssssssssssHo",
        "ohsslesslessHo",
        "ohsseesseessHo",
        "ohscsssssscsHo",
        "ohssssoossssHo",
        "..osssssssso..",
        "...oooooooo...",
    ])

    /// まばたき（目を閉じた顔）。目のドットを横線に置き換えただけの差分。
    static let headBlink = PixelSprite([
        "....oooooo....",
        "..oohhhhhhoo..",
        ".ohhhhhhhhhho.",
        "ohhhhhhhhhhhHo",
        "ohhhhhhhhhhhHo",
        "ohhssssssssHHo",
        "ohssssssssssHo",
        "ohssssssssssHo",
        "ohssoossoossHo",
        "ohscsssssscsHo",
        "ohssssoossssHo",
        "..osssssssso..",
        "...oooooooo...",
    ])

    static let headWidth = 14
    static let headHeight = 13

    // MARK: - 胴（幅 8 / 10 / 12 × 高さ 8）

    static func body(_ girth: CharacterBuild.Girth) -> PixelSprite {
        switch girth {
        case .slim: return bodySlim
        case .normal: return bodyNormal
        case .wide: return bodyWide
        }
    }

    static func bodyWidth(_ girth: CharacterBuild.Girth) -> Int {
        switch girth {
        case .slim: return 8
        case .normal: return 10
        case .wide: return 12
        }
    }

    // 上 5 段がタンクトップ、下 3 段がショートパンツ。
    // 上下の段数を変えると「ワンピースを着ている」ように見えてしまうので、この比率は崩さない。

    private static let bodySlim = PixelSprite([
        "osswwsso",
        "oswwwwso",
        "owwwwwwo",
        "owwwwwwo",
        "oWWWWWWo",
        "oppppppo",
        "oppppppo",
        "oPPPPPPo",
    ])

    private static let bodyNormal = PixelSprite([
        "osswwwwsso",
        "oswwwwwwso",
        "owwwwwwwwo",
        "owwwwwwwwo",
        "oWWWWWWWWo",
        "oppppppppo",
        "oppppppppo",
        "oPPPPPPPPo",
    ])

    private static let bodyWide = PixelSprite([
        "osswwwwwwsso",
        "oswwwwwwwwso",
        "owwwwwwwwwwo",
        "owwwwwwwwwwo",
        "oWWWWWWWWWWo",
        "oppppppppppo",
        "oppppppppppo",
        "oPPPPPPPPPPo",
    ])

    static let bodyHeight = 8

    // MARK: - 腕（幅 3 / 4 × 高さ 5）

    static func arm(_ weight: CharacterBuild.Limb) -> PixelSprite {
        weight == .thin ? armThin : armThick
    }

    static func armWidth(_ weight: CharacterBuild.Limb) -> Int {
        weight == .thin ? 4 : 5
    }

    // 手足は輪郭 1 ドットが両側に入るぶん、幅を 4 以上にしないと肌が 1 ドットしか残らず
    // 「黒い棒」に見えてしまう。内側の輪郭は胴の輪郭に重ねて 1 本に見せる（描画側でずらす）。

    private static let armThin = PixelSprite([
        "osso",
        "osso",
        "osso",
        "osso",
        "oooo",
    ])

    private static let armThick = PixelSprite([
        "osSso",
        "osSso",
        "osSso",
        "osSso",
        "ooooo",
    ])

    static let armHeight = 5

    // MARK: - 脚（幅 3 / 4 × 高さ 4）

    static func leg(_ weight: CharacterBuild.Limb) -> PixelSprite {
        weight == .thin ? legThin : legThick
    }

    static func legWidth(_ weight: CharacterBuild.Limb) -> Int {
        weight == .thin ? 4 : 5
    }

    private static let legThin = PixelSprite([
        "osso",
        "osso",
        "osso",
        "dddd",
    ])

    private static let legThick = PixelSprite([
        "osSso",
        "osSso",
        "osSso",
        "ddddd",
    ])

    static let legHeight = 4

    // MARK: - 小道具

    /// ダンベル（カール中に手に持つ）。
    static let dumbbell = PixelSprite([
        "d...d",
        "dmmmd",
        "d...d",
    ])

    /// リュック（遠征中に背負う）。
    static let backpack = PixelSprite([
        "..kk..",
        ".kkkk.",
        "kkkkkk",
        "kkkkkk",
        "kkkkkk",
        "kkkkkk",
        ".kkkk.",
    ])

    // MARK: - 装備（部位 × レア度）

    /// 頭の装備。幅は頭に合わせて 14。
    static func headGear(_ rarity: Expedition.Rarity) -> PixelSprite {
        switch rarity {
        case .common: return headband
        case .rare: return cap
        case .epic: return crown
        }
    }

    /// 頭の装備を頭のどこに置くか（頭スプライトの上端からのドット数）。
    static func headGearOffset(_ rarity: Expedition.Rarity) -> Int {
        switch rarity {
        case .common: return 5
        case .rare: return 0
        case .epic: return -3
        }
    }

    private static let headband = PixelSprite([
        ".orrrrrrrrrro.",
        ".orrrrrrrrrro.",
    ])

    private static let cap = PixelSprite([
        "....oooooo....",
        ".oorrrrrrrroo.",
        "orrrrrrrrrrrro",
        "..rrrrrrrrrr..",
    ])

    private static let crown = PixelSprite([
        "...r..rr..r...",
        "...rr.rr.rr...",
        "...rrrrrrrr...",
        "...rrrrrrrr...",
    ])

    /// 手の装備。腕の先に重ねる。
    static func handGear(_ rarity: Expedition.Rarity) -> PixelSprite {
        switch rarity {
        case .common: return wristband
        case .rare: return grip
        case .epic: return goldenGrip
        }
    }

    private static let wristband = PixelSprite([
        "rrr",
        "rrr",
    ])

    private static let grip = PixelSprite([
        "rrr",
        "rrr",
        "rrr",
    ])

    private static let goldenGrip = PixelSprite([
        "rrrr",
        "rlrr",
        "rrrr",
    ])

    // MARK: - 家具（部屋に置く）

    static let plant = PixelSprite([
        "..g..g..",
        ".ggg.gg.",
        "gg.ggggg",
        ".g.ggg.g",
        "...ggg..",
        "..kkkk..",
        "..kkkk..",
        "...kk...",
    ])

    static let dumbbellRack = PixelSprite([
        "oooooooooooo",
        "ommommommomo",
        "oooooooooooo",
        "ommommommomo",
        "oooooooooooo",
        "o..........o",
        "o..........o",
    ])

    static let bench = PixelSprite([
        "..dddddddd..",
        ".dddddddddd.",
        "..oo....oo..",
        "..oo....oo..",
        "..oo....oo..",
        ".oooo..oooo.",
    ])

    static let barbell = PixelSprite([
        "d........d",
        "d.mmmmmm.d",
        "dd......dd",
        "d........d",
    ])

    /// 帰還した遠征の宝箱。
    static let chest = PixelSprite([
        "..oooooooo..",
        ".okkkkkkkko.",
        "okkkkkkkkkko",
        "ommmmmmmmmmo",
        "okkkkkkkkkko",
        "okkkkmmkkkko",
        "okkkkmmkkkko",
        "oooooooooooo",
    ])
}
