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

    /// 向きと目の開閉から頭の絵を選ぶ。
    ///
    /// **向きは頭だけで伝える**。低解像度のスプライトでは、体を向きごとに描き分けても
    /// 数ドットしか変わらず労力に見合わない。輪郭が大きく変わるのは髪と顔なので、そこに絵を集中させる。
    /// 横向きは右向きで持ち、左向きは描画側で反転して使う（背面はまばたきの描き分けが要らない）。
    static func head(facing: CharacterScene.Facing, blinking: Bool) -> PixelSprite {
        switch facing {
        case .up: return headBack
        case .left, .right: return blinking ? headSideBlink : headSide
        case .down: return blinking ? headBlink : headFront
        }
    }

    /// 通常の顔。
    static let headFront = PixelSprite([
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

    /// 背面。顔が無いぶん、つむじで「後ろ姿」だと分かるようにする。
    static let headBack = PixelSprite([
        "....oooooo....",
        "..oohhhhhhoo..",
        ".ohhhhhhhhhho.",
        "ohhhhhhhhhhhho",
        "ohhhhHHhhhhhho",
        "ohhhhHhHhhhhho",
        "ohhhhhHHhhhhho",
        "ohhhhhhhhhhhho",
        "ohhhhhhhhhhhho",
        "ohhhhhhhhhhhho",
        "ohhhhhhhhhhhho",
        "..ohhhhhhhho..",
        "...oooooooo...",
    ])

    /// 横向き（右向き）。左向きは反転して使う。
    static let headSide = PixelSprite([
        "...oooooo.....",
        ".oohhhhhhoo...",
        "ohhhhhhhhhho..",
        "ohhhhhhhhhhho.",
        "ohhhhhhhhhssso",
        "ohhhhhhhssssso",
        "ohhhhhhsseesso",
        "ohhhhhhsseesso",
        "ohhhhhhsscssso",
        "ohhhhhhsssooso",
        ".ohhhhhssssso.",
        "..ohhhssssso..",
        "...oooooooo...",
    ])

    static let headSideBlink = PixelSprite([
        "...oooooo.....",
        ".oohhhhhhoo...",
        "ohhhhhhhhhho..",
        "ohhhhhhhhhhho.",
        "ohhhhhhhhhssso",
        "ohhhhhhhssssso",
        "ohhhhhhsssssso",
        "ohhhhhhssoosso",
        "ohhhhhhsscssso",
        "ohhhhhhsssooso",
        ".ohhhhhssssso.",
        "..ohhhssssso..",
        "...oooooooo...",
    ])

    // MARK: - コーチの頭

    /// AI コーチ（#79）の顔。プレイヤーと同じ画枠・同じ骨格を使い、**帽子で人物を描き分ける**。
    /// 部屋にもう 1 人立たせるので、シルエットが被ると「自分が 2 人いる」ように見えてしまう。
    static func coachHead(blinking: Bool) -> PixelSprite {
        blinking ? coachHeadBlink : coachHeadFront
    }

    private static let coachHeadFront = PixelSprite([
        "....oooooo....",
        "..oowwwwwwoo..",
        ".owwwwwwwwwwo.",
        "owwwwwwwwwwwwo",
        "owwwwwwwwwwwwo",
        "oWWWWWWWWWWWWo",
        "oooooooooooooo",
        "ohsslesslessHo",
        "ohsseesseessHo",
        "ohscsssssscsHo",
        "ohssssoossssHo",
        "..osssssssso..",
        "...oooooooo...",
    ])

    private static let coachHeadBlink = PixelSprite([
        "....oooooo....",
        "..oowwwwwwoo..",
        ".owwwwwwwwwwo.",
        "owwwwwwwwwwwwo",
        "owwwwwwwwwwwwo",
        "oWWWWWWWWWWWWo",
        "oooooooooooooo",
        "ohssssssssssHo",
        "ohssoossoossHo",
        "ohscsssssscsHo",
        "ohssssoossssHo",
        "..osssssssso..",
        "...oooooooo...",
    ])

    /// コーチが持つクリップボード。何をする人か一目で分かるようにする。
    /// 身長 24 ドットに対して縦長すぎると体を覆ってしまうので 6 段に抑える。
    static let clipboard = PixelSprite([
        "..o..",
        "ooooo",
        "olllo",
        "oldlo",
        "olllo",
        "ooooo",
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

    // 上 4 段がタンクトップ、下 3 段がショートパンツ。
    // 上下の段数を変えると「ワンピースを着ている」ように見えてしまうので、この比率は崩さない。
    // 右端 1 列を影にして、真四角の板に見えないようにしている。

    private static let bodySlim = PixelSprite([
        "osswwSso",
        "oswwwWso",
        "owwwwwWo",
        "oWWWWWWo",
        "opppppPo",
        "opppppPo",
        "oPPPPPPo",
    ])

    private static let bodyNormal = PixelSprite([
        "osswwwwSso",
        "oswwwwwWso",
        "owwwwwwwWo",
        "oWWWWWWWWo",
        "opppppppPo",
        "opppppppPo",
        "oPPPPPPPPo",
    ])

    private static let bodyWide = PixelSprite([
        "osswwwwwwSso",
        "oswwwwwwwWso",
        "owwwwwwwwwWo",
        "oWWWWWWWWWWo",
        "opppppppppPo",
        "opppppppppPo",
        "oPPPPPPPPPPo",
    ])

    static let bodyHeight = 7

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
        "osso",
        "dddd",
    ])

    private static let legThick = PixelSprite([
        "osSso",
        "osSso",
        "osSso",
        "osSso",
        "ddddd",
    ])

    static let legHeight = 5

    // MARK: - 小道具

    /// ダンベル（カール中に手に持つ）。
    static let dumbbell = PixelSprite([
        "d...d",
        "dmmmd",
        "d...d",
    ])

    /// リュック（遠征中に背負う）。留め具と肩ベルトを入れて、ただの塊に見えないようにする。
    static let backpack = PixelSprite([
        "..oooo..",
        ".okkkko.",
        "okkkkkko",
        "okkkkkko",
        "ommmmmmo",
        "okkkkkko",
        "okkmmkko",
        "okkkkkko",
        ".oooooo.",
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

    /// ベンチ。座面が薄いと鳥居に見えるので、厚みを持たせる。
    static let bench = PixelSprite([
        "..dddddddd..",
        ".dddddddddd.",
        ".dddddddddd.",
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

    /// 帰還した遠征の宝箱。閉じている / 開きかけ / 開いた の 3 コマ。
    static func chest(_ frame: Int) -> PixelSprite {
        switch max(0, frame) % 3 {
        case 1: return chestAjar
        case 2: return chestOpen
        default: return chestClosed
        }
    }

    static let chestClosed = PixelSprite([
        "..oooooooo..",
        ".okkkkkkkko.",
        "okkkkkkkkkko",
        "ommmmmmmmmmo",
        "okkkkkkkkkko",
        "okkkkmmkkkko",
        "okkkkmmkkkko",
        "oooooooooooo",
    ])

    private static let chestAjar = PixelSprite([
        ".oooooooooo.",
        "okkkkkkkkkko",
        "ommmmmmmmmmo",
        "..llllllll..",
        "okkkkkkkkkko",
        "okkkkmmkkkko",
        "okkkkmmkkkko",
        "oooooooooooo",
    ])

    private static let chestOpen = PixelSprite([
        "okkkkkkkkkko",
        "ommmmmmmmmmo",
        ".llllllllll.",
        ".llllllllll.",
        "okkkkkkkkkko",
        "okkkkmmkkkko",
        "okkkkmmkkkko",
        "oooooooooooo",
    ])

    // MARK: - 家具（続きが増えるほど部屋が埋まる）

    static let mirror = PixelSprite([
        "oooooooo",
        "obbbbbbo",
        "obbbbllo",
        "obbblbbo",
        "obbbbbbo",
        "obbbbbbo",
        "obbbbbbo",
        "obbbbbbo",
        "obbbbbbo",
        "obbbbbbo",
        "oooooooo",
        "..o..o..",
        "..o..o..",
        ".ooooooo",
    ])

    static let waterBottle = PixelSprite([
        ".oo.",
        ".oo.",
        "oooo",
        "obbo",
        "obbo",
        "obbo",
        "obbo",
        "oooo",
    ])

    /// タオル掛け。バーにタオルが掛かって垂れている形にする（枠で囲うと額縁に見える）。
    static let towelRack = PixelSprite([
        "oooooooooo",
        ".ffffffff.",
        ".ffffffff.",
        ".ffffffff.",
        ".ffffffff.",
        ".fffffff..",
        "..fffff...",
        "...fff....",
    ])

    static let wallClock = PixelSprite([
        ".oooooo.",
        "ooffffoo",
        "offofffo",
        "offofffo",
        "offoooff",
        "offffffo",
        "ooffffoo",
        ".oooooo.",
    ])

    /// ケトルベル。取っ手を細いアーチにしないとハンドバッグに見える。
    static let kettlebell = PixelSprite([
        "..oooo..",
        ".oo..oo.",
        ".o....o.",
        "..oooo..",
        ".ommmmo.",
        "ommmmmmo",
        "ommmmmmo",
        ".oooooo.",
    ])

    /// サンドバッグ。細いとボトルに見えるので、幅を取って締めバンドを 2 本入れる。
    static let punchingBag = PixelSprite([
        "...oo...",
        "...oo...",
        ".oooooo.",
        ".oddddo.",
        ".oddddo.",
        ".oddddo.",
        ".ommmmo.",
        ".oddddo.",
        ".oddddo.",
        ".oddddo.",
        ".ommmmo.",
        ".oddddo.",
        ".oddddo.",
        ".oddddo.",
        ".oooooo.",
        "........",
    ])

    /// ポスター。ダンベルの図。プレートを枠から 1 ドット離さないと、
    /// 枠とつながって砂時計のような形に見える。
    static let poster = PixelSprite([
        "oooooooo",
        "obbbbbbo",
        "obbbbbbo",
        "obdbbdbo",
        "obdmmdbo",
        "obdbbdbo",
        "obbbbbbo",
        "obffffbo",
        "oooooooo",
    ])

    // MARK: - 演出（仕草に添える小物）

    /// 汗。スクワット中などに飛ばす。
    static let sweatDrop = PixelSprite([
        ".o.",
        "obo",
        "obo",
        ".o.",
    ])

    /// きらめき。進化直後や自己ベスト時に散らす。
    static let sparkle = PixelSprite([
        "..r..",
        "..r..",
        "rrlrr",
        "..r..",
        "..r..",
    ])

    /// 湯気。オーラ装備の表現に使う。
    static let steamWisp = PixelSprite([
        ".r.",
        "r..",
        ".r.",
        "..r",
        ".r.",
        "r..",
    ])

    /// ハート。キャラをタップしたときに浮かせる。
    static let heart = PixelSprite([
        ".rr.rr.",
        "rrrrrrr",
        "rrrrrrr",
        ".rrrrr.",
        "..rrr..",
        "...r...",
    ])

    /// 音符。ハートと交互に出して、同じ反応の繰り返しに見えないようにする。
    static let note = PixelSprite([
        "...rr",
        "...rr",
        "...rr",
        "...rr",
        ".rrrr",
        "rrrr.",
    ])

    /// 葉。プロテインの香りの表現に使う。
    static let leafBit = PixelSprite([
        ".gg.",
        "gggg",
        "gggg",
        ".gg.",
    ])
}
