#if DEBUG
import SwiftUI

/// ドット絵の一覧（DEBUG 限定）。製品ビルドには含まれない。
///
/// 絵をコードで持っている以上、崩れに気づけるのは実際に描いてみたときだけ。
/// `xcrun simctl launch <device> com.gymnee.app.dev -gymneeDemo -gymneeScreen pixelart`
/// で開き、スクリーンショット 1 枚で全スプライトを目視できるようにしてある。
struct PixelArtGallery: View {

    /// 見たい範囲。1 画面に収めてスクショで確認できるよう、起動引数で切り替える。
    /// `-gymneeScreen pixelart` / `pixelart-items` / `pixelart-room` / `pixelart-pets`
    enum Section: String {
        case character, items, room, pets
    }

    var section: Section = .character

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    switch section {
                    case .character:
                        characterSection
                    case .items:
                        itemSection
                        courseSection
                    case .room:
                        furnitureSection
                        effectSection
                    case .pets:
                        petSection
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("ドット絵一覧")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - ペット

    /// ペットは種類 × 向き（正面 / まばたき / 横 / 背面）。左向きは横向きの反転なので出さない。
    private var petSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(PetCatalog.all) { pet in
                SectionHeader(title: pet.name)
                LazyVGrid(columns: grid(minimum: 76), spacing: Theme.Spacing.md) {
                    ForEach(petCells(pet.id), id: \.name) { cell in
                        labelled(cell.name) {
                            PixelSpriteView(
                                sprite: cell.sprite,
                                palette: PixelPetArt.palette(petId: pet.id),
                                side: 64
                            )
                        }
                    }
                }
            }
        }
    }

    private func petCells(_ petId: String) -> [(name: String, sprite: PixelSprite)] {
        [
            ("正面", PixelPetArt.sprite(petId: petId, facing: .down, blink: false)),
            ("まばたき", PixelPetArt.sprite(petId: petId, facing: .down, blink: true)),
            ("横", PixelPetArt.sprite(petId: petId, facing: .right, blink: false)),
            ("背面", PixelPetArt.sprite(petId: petId, facing: .up, blink: false)),
        ]
    }

    // MARK: - キャラ（体格 × 仕草）

    private var characterSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "キャラ（体格 12 通り）")
            LazyVGrid(columns: grid(minimum: 76), spacing: Theme.Spacing.md) {
                ForEach(Array(builds.enumerated()), id: \.offset) { _, build in
                    labelled("胴\(build.girth.rawValue)腕\(build.arm.rawValue)脚\(build.leg.rawValue)") {
                        CharacterPreview(build: build, frame: .standing, skin: SkinCatalog.all[0])
                    }
                }
            }

            SectionHeader(title: "向き 4 方向 × 歩行コマ")
            LazyVGrid(columns: grid(minimum: 76), spacing: Theme.Spacing.md) {
                ForEach(Array(walkCells.enumerated()), id: \.offset) { _, cell in
                    labelled(cell.name) {
                        CharacterPreview(
                            build: CharacterBuild(girth: .normal, arm: .thick, leg: .thick),
                            frame: cell.frame,
                            skin: SkinCatalog.all[0],
                            facing: cell.facing
                        )
                    }
                }
            }

            SectionHeader(title: "仕草")
            LazyVGrid(columns: grid(minimum: 76), spacing: Theme.Spacing.md) {
                ForEach(Array(emoteFrames.enumerated()), id: \.offset) { _, entry in
                    labelled(entry.name) {
                        CharacterPreview(
                            build: CharacterBuild(girth: .normal, arm: .thick, leg: .thick),
                            frame: entry.frame,
                            skin: SkinCatalog.all[0]
                        )
                    }
                }
            }

            SectionHeader(title: "スキン")
            LazyVGrid(columns: grid(minimum: 76), spacing: Theme.Spacing.md) {
                ForEach(SkinCatalog.all) { skin in
                    labelled(skin.name) {
                        CharacterPreview(
                            build: CharacterBuild(girth: .normal, arm: .thick, leg: .thick),
                            frame: .standing,
                            skin: skin
                        )
                    }
                }
            }

            SectionHeader(title: "AI コーチ（#79）")
            LazyVGrid(columns: grid(minimum: 76), spacing: Theme.Spacing.md) {
                labelled("通常") {
                    CharacterPreview(
                        build: PixelCharacterRenderer.coachBuild,
                        frame: .standing,
                        skin: PixelCharacterRenderer.coachSkin,
                        role: .coach
                    )
                }
                labelled("まばたき") {
                    CharacterPreview(
                        build: PixelCharacterRenderer.coachBuild,
                        frame: PixelCharacterLayout.frame(for: pose(.emoting(.rest), blink: 1)),
                        skin: PixelCharacterRenderer.coachSkin,
                        role: .coach
                    )
                }
                labelled("自分と並べて") {
                    CharacterPreview(
                        build: CharacterBuild(girth: .normal, arm: .thick, leg: .thick),
                        frame: .standing,
                        skin: SkinCatalog.all[0]
                    )
                }
            }

            SectionHeader(title: "装備を着せた状態")
            LazyVGrid(columns: grid(minimum: 76), spacing: Theme.Spacing.md) {
                ForEach(Expedition.Rarity.allCases, id: \.self) { rarity in
                    labelled(rarity.label) {
                        CharacterPreview(
                            build: CharacterBuild(girth: .wide, arm: .thick, leg: .thick),
                            frame: .standing,
                            skin: SkinCatalog.all[0],
                            equipped: fullSet(rarity)
                        )
                    }
                }
            }
        }
    }

    // MARK: - 戦利品

    private var itemSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "戦利品 12 種")
            LazyVGrid(columns: grid(minimum: 82), spacing: Theme.Spacing.md) {
                ForEach(Expedition.items) { item in
                    labelled(item.name) {
                        PixelSpriteView(
                            sprite: PixelItemArt.icon(for: item),
                            palette: .item(rarity: item.rarity),
                            side: 64
                        )
                    }
                }
            }
        }
    }

    private var courseSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "遠征コース")
            LazyVGrid(columns: grid(minimum: 82), spacing: Theme.Spacing.md) {
                ForEach(Expedition.courses) { course in
                    labelled(course.title) {
                        PixelSpriteView(sprite: PixelItemArt.course(id: course.id), palette: .neutral, side: 64)
                    }
                }
            }
        }
    }

    // MARK: - 家具・演出

    private var furnitureSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "家具・小物")
            LazyVGrid(columns: grid(minimum: 82), spacing: Theme.Spacing.md) {
                ForEach(Array(furniture.enumerated()), id: \.offset) { _, entry in
                    labelled(entry.name) {
                        PixelSpriteView(sprite: entry.sprite, palette: .neutral, side: 64)
                    }
                }
            }
        }
    }

    private var effectSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "演出")
            LazyVGrid(columns: grid(minimum: 82), spacing: Theme.Spacing.md) {
                ForEach(Array(effects.enumerated()), id: \.offset) { _, entry in
                    labelled(entry.name) {
                        PixelSpriteView(sprite: entry.sprite, palette: .item(rarity: .epic), side: 48)
                    }
                }
            }
        }
    }

    // MARK: - 素材

    private var builds: [CharacterBuild] {
        CharacterBuild.Girth.allCases.flatMap { girth in
            CharacterBuild.Limb.allCases.flatMap { arm in
                CharacterBuild.Limb.allCases.map { leg in
                    CharacterBuild(girth: girth, arm: arm, leg: leg)
                }
            }
        }
    }

    /// 向き 4 方向 × 歩行 4 コマ。LazyVGrid は ForEach の入れ子を展開しないので、先に平坦化する。
    private var walkCells: [(name: String, facing: CharacterScene.Facing, frame: PixelCharacterLayout.Frame)] {
        CharacterScene.Facing.allCases.flatMap { facing in
            (0..<PixelCharacterLayout.walkFrameCount).map { step in
                let phase = (Double(step) + 0.5) / Double(PixelCharacterLayout.walkFrameCount)
                return (
                    "\(facing.rawValue)\(step)",
                    facing,
                    PixelCharacterLayout.frame(for: pose(.walking, walkPhase: phase))
                )
            }
        }
    }

    private var emoteFrames: [(name: String, frame: PixelCharacterLayout.Frame)] {
        var result: [(String, PixelCharacterLayout.Frame)] = []
        for step in 0..<PixelCharacterLayout.walkFrameCount {
            let phase = (Double(step) + 0.5) / Double(PixelCharacterLayout.walkFrameCount)
            result.append(("歩行\(step)", PixelCharacterLayout.frame(for: pose(.walking, walkPhase: phase))))
        }
        for emote in CharacterScene.Emote.allCases {
            result.append((
                "\(emote.rawValue)",
                PixelCharacterLayout.frame(for: pose(.emoting(emote), emotePhase: 0.25))
            ))
        }
        result.append(("まばたき", PixelCharacterLayout.frame(for: pose(.emoting(.rest), blink: 1))))
        return result
    }

    private var furniture: [(name: String, sprite: PixelSprite)] {
        [
            ("植物", PixelCharacterArt.plant),
            ("ラック", PixelCharacterArt.dumbbellRack),
            ("ベンチ", PixelCharacterArt.bench),
            ("バーベル", PixelCharacterArt.barbell),
            ("鏡", PixelCharacterArt.mirror),
            ("ボトル", PixelCharacterArt.waterBottle),
            ("タオル", PixelCharacterArt.towelRack),
            ("時計", PixelCharacterArt.wallClock),
            ("ケトルベル", PixelCharacterArt.kettlebell),
            ("サンドバッグ", PixelCharacterArt.punchingBag),
            ("ポスター", PixelCharacterArt.poster),
            ("宝箱(閉)", PixelCharacterArt.chest(0)),
            ("宝箱(半開)", PixelCharacterArt.chest(1)),
            ("宝箱(開)", PixelCharacterArt.chest(2)),
            ("リュック", PixelCharacterArt.backpack),
            ("ダンベル", PixelCharacterArt.dumbbell),
        ]
    }

    private var effects: [(name: String, sprite: PixelSprite)] {
        [
            ("汗", PixelCharacterArt.sweatDrop),
            ("きらめき", PixelCharacterArt.sparkle),
            ("湯気", PixelCharacterArt.steamWisp),
            ("葉", PixelCharacterArt.leafBit),
        ]
    }

    private func fullSet(_ rarity: Expedition.Rarity) -> [Expedition.Slot: Expedition.Item] {
        var result: [Expedition.Slot: Expedition.Item] = [:]
        for slot in Expedition.Slot.allCases {
            if let item = Expedition.items(in: slot).first(where: { $0.rarity == rarity }) {
                result[slot] = item
            }
        }
        return result
    }

    private func pose(
        _ behavior: CharacterScene.Behavior,
        walkPhase: Double = 0,
        emotePhase: Double = 0,
        blink: Double = 0
    ) -> CharacterScene.Pose {
        CharacterScene.Pose(
            position: CGPoint(x: 0.5, y: 0.5), facing: .down, behavior: behavior,
            walkPhase: walkPhase, emotePhase: emotePhase, breathPhase: 0, blink: blink
        )
    }

    private func grid(minimum: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: Theme.Spacing.md)]
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            content()
                .frame(height: 80)
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}

/// キャラ 1 体を静止画として描くプレビュー（一覧用）。
private struct CharacterPreview: View {
    let build: CharacterBuild
    let frame: PixelCharacterLayout.Frame
    let skin: CharacterSkin
    var equipped: [Expedition.Slot: Expedition.Item] = [:]
    var facing: CharacterScene.Facing = .down
    var role: PixelCharacterRenderer.Role = .trainee

    var body: some View {
        Canvas { context, size in
            let dot = max(1, (size.height / CGFloat(PixelCharacterArt.canvasHeight)).rounded(.down))
            PixelCharacterRenderer.draw(
                in: &context,
                look: PixelCharacterRenderer.Look(
                    build: build, skin: skin, equipped: equipped,
                    stage: .rookie, carriesPack: false, nameTag: nil, role: role
                ),
                frame: frame,
                facing: facing,
                feet: CGPoint(x: size.width / 2, y: size.height - dot),
                dot: dot
            )
        }
    }
}
#endif
