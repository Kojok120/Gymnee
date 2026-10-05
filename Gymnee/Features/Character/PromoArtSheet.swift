#if DEBUG
import SwiftUI

/// ストア掲載画像の素材を描く（DEBUG 限定。issue #135）。
///
/// マゼンタ一色の背景に、キャラ・ボス・ペットを決まった格子（2列×4段、1マス 210×215pt）に並べる。
/// 上端は Dynamic Island を避けて 66pt 下げる。
/// `-gymneeScreen promo-sheet-<0|1|2>` で開いてスクショを撮り、
/// `docs/release_information/store_panels/promo/build_sprites.sh` が背景を抜いて1体ずつ切り出す。
/// 背景を抜くので、縁がにじむもの（オーラ・グラデーション）はここでは描かない。
struct PromoArtSheet: View {
    let page: Int

    static let chromaKey = Color(red: 1, green: 0, blue: 1)
    static let cellSize = CGSize(width: 210, height: 215)
    static func cellOrigin(_ index: Int) -> CGPoint {
        CGPoint(x: 10 + CGFloat(index % 2) * 215, y: 66 + CGFloat(index / 2) * 220)
    }

    enum Cell {
        case person(PixelCharacterRenderer.Look, PixelCharacterLayout.Frame)
        case boss(String, PartyBoss.Tier)
        case pet(String)
    }

    private static func look(
        skin: String, hair: String, accessory: String, build: CharacterBuild,
        gear: [String], role: PixelCharacterRenderer.Role = .trainee
    ) -> PixelCharacterRenderer.Look {
        var equipped: [Expedition.Slot: Expedition.Item] = [:]
        for id in gear {
            if let item = Expedition.item(id: id) { equipped[item.slot] = item }
        }
        return PixelCharacterRenderer.Look(
            build: build, skin: role == .coach ? PixelCharacterRenderer.coachSkin : SkinCatalog.skin(id: skin),
            equipped: equipped, stage: .trainee, carriesPack: false, nameTag: nil, role: role,
            hairStyleId: hair, accessoryId: accessory
        )
    }

    private static func pose(raised: Bool = false, dumbbell: Bool = false) -> PixelCharacterLayout.Frame {
        var frame = PixelCharacterLayout.Frame.standing
        frame.armsRaised = raised
        frame.holdsDumbbell = dumbbell
        return frame
    }

    static let people: [Cell] = [
        .person(look(skin: "classic", hair: "short", accessory: "glasses",
                     build: .init(girth: .wide, arm: .thick, leg: .thick), gear: ["crown", "champion-belt"]), pose(raised: true)),
        .person(look(skin: "midnight", hair: "ponytail", accessory: "none",
                     build: .init(girth: .normal, arm: .thick, leg: .thin), gear: ["cap", "power-grip"]), pose(dumbbell: true)),
        .person(look(skin: "sunset", hair: "long", accessory: "earphones",
                     build: .init(girth: .slim, arm: .thin, leg: .thin), gear: ["sweat-band"]), pose(raised: true)),
        .person(look(skin: "gymnee", hair: "buzz", accessory: "shades",
                     build: .init(girth: .wide, arm: .thick, leg: .thick), gear: ["golden-grip", "lifting-belt"]), pose(dumbbell: true)),
        .person(look(skin: "classic", hair: "long", accessory: "none",
                     build: .init(girth: .slim, arm: .thin, leg: .thick), gear: ["wristband"]), pose(raised: true)),
        .person(look(skin: "midnight", hair: "buzz", accessory: "glasses",
                     build: .init(girth: .wide, arm: .thick, leg: .thin), gear: ["crown"]), pose(dumbbell: true)),
        .person(look(skin: "sunset", hair: "ponytail", accessory: "shades",
                     build: .init(girth: .normal, arm: .thin, leg: .thick), gear: ["cap", "cloth-belt"]), pose(raised: true)),
        .person(look(skin: "gymnee", hair: "short", accessory: "earphones",
                     build: .init(girth: .normal, arm: .thick, leg: .thick), gear: ["sweat-band", "champion-belt"]), pose(dumbbell: true)),
    ]

    static func cells(page: Int) -> [Cell] {
        switch page {
        case 1:
            return PartyBoss.catalog.map { .boss($0.id, .strong) } + PartyBoss.catalog.map { .boss($0.id, .medium) }
        case 2:
            return PartyBoss.catalog.map { .boss($0.id, .weak) } + [
                .pet("shiba"), .pet("tabby"),
                .person(look(skin: "classic", hair: "short", accessory: "none",
                             build: .init(girth: .normal, arm: .thick, leg: .thick), gear: [], role: .coach), pose(raised: true)),
                .person(look(skin: "classic", hair: "short", accessory: "none",
                             build: .init(girth: .slim, arm: .thin, leg: .thin), gear: []), pose()),
            ]
        default:
            return people
        }
    }

    var body: some View {
        Canvas { context, _ in
            for (index, cell) in Self.cells(page: page).enumerated() {
                let origin = Self.cellOrigin(index)
                let feet = CGPoint(x: origin.x + Self.cellSize.width / 2, y: origin.y + Self.cellSize.height - 4)
                switch cell {
                case let .person(look, frame):
                    PixelCharacterRenderer.draw(in: &context, look: look, frame: frame, facing: .down, feet: feet, dot: 8)
                case let .boss(id, tier):
                    let sprite = PixelBossArt.sprite(bossId: id, tier: tier)
                    let dot: CGFloat = 11
                    let at = CGPoint(x: (feet.x - CGFloat(sprite.width) * dot / 2).rounded(),
                                     y: (feet.y - CGFloat(sprite.height) * dot).rounded())
                    context.drawPixels(sprite, at: at, dot: dot, palette: PixelBossArt.palette(bossId: id, tier: tier))
                case let .pet(id):
                    let sprite = PixelPetArt.sprite(petId: id, facing: .down, blink: false)
                    let dot: CGFloat = 10
                    let at = CGPoint(x: (feet.x - CGFloat(sprite.width) * dot / 2).rounded(),
                                     y: (feet.y - CGFloat(sprite.height) * dot).rounded())
                    context.drawPixels(sprite, at: at, dot: dot, palette: PixelPetArt.palette(petId: id))
                }
            }
        }
        .background(Self.chromaKey)
        .ignoresSafeArea()
        .statusBarHidden()
    }
}
#endif
