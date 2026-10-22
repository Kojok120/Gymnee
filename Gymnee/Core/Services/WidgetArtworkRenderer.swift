import SwiftUI
import WidgetKit

/// ウィジェットと Live Activity 用の絵を描いて App Group に置く（issue #155）。置き場所と読み方は `WidgetArtwork`。
///
/// 描くのは見た目や今週のボスが変わったときだけ（指紋で比べる）。書いたらウィジェットを読み直させる。
@MainActor
enum WidgetArtworkRenderer {
    private static var characterFingerprint: String?
    private static var bossFingerprint: String?

    /// 自分のキャラ（正面立ち）。1 ドット = 4px の PNG。
    static func updateCharacter(_ look: PartyBoss.MemberLook) {
        guard look.fingerprint != characterFingerprint else { return }
        let figure = PixelCharacterRenderer.Look(memberLook: look)
        let side = CGFloat(PixelCharacterArt.canvasWidth) * dot
        let height = CGFloat(PixelCharacterArt.canvasHeight + 4) * dot
        let view = Canvas { context, size in
            PixelCharacterRenderer.draw(
                in: &context, look: figure, frame: .standing, facing: .down,
                feet: CGPoint(x: size.width / 2, y: size.height - dot), dot: dot
            )
        }
        .frame(width: side, height: height)
        guard write(view, to: WidgetArtwork.characterFile) else { return }
        characterFingerprint = look.fingerprint
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 今週のボスの絵と残り HP。パーティが無い・読めていないときは消す（ウィジェットはボスの欄を出さない）。
    static func updateBoss(_ status: PartyBoss.Status?) {
        let boss = status.map {
            WidgetArtwork.Boss(name: $0.boss?.name ?? "今週のボス", remainingHP: $0.remainingHP, totalHP: $0.hp,
                               defeated: $0.defeated, weekStart: $0.weekStart)
        }
        let fingerprint = status.map { "\($0.bossId)|\($0.tier.rawValue)|\($0.remainingHP)/\($0.hp)|\($0.defeated)|\($0.weekStart.timeIntervalSince1970)" }
        guard fingerprint != bossFingerprint else { return }
        if let status {
            let sprite = PixelBossArt.sprite(bossId: status.bossId, tier: status.tier)
            let palette = PixelBossArt.palette(bossId: status.bossId, tier: status.tier)
            let view = Canvas { context, _ in
                context.drawPixels(sprite, at: .zero, dot: dot, palette: palette)
            }
            .frame(width: CGFloat(sprite.width) * dot, height: CGFloat(sprite.height) * dot)
            guard write(view, to: WidgetArtwork.bossFile) else { return }
        }
        WidgetArtwork.saveBoss(boss)
        bossFingerprint = fingerprint
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 1 ドットの大きさ（px）。ウィジェットは補間なしで拡大して貼る。
    private static let dot: CGFloat = 4

    private static func write(_ view: some View, to name: String) -> Bool {
        guard let url = WidgetArtwork.fileURL(name) else { return false }
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = false
        guard let data = renderer.uiImage?.pngData() else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

extension PixelCharacterRenderer.Look {
    /// 送受信用の見た目（`PartyBoss.MemberLook`）から描く見た目を組み立てる。知らない id は既定に落とす。
    init(memberLook look: PartyBoss.MemberLook) {
        self.init(
            build: look.build,
            skin: SkinCatalog.skin(id: look.skinId),
            equipped: look.equippedItems,
            stage: look.stageValue,
            carriesPack: false,
            nameTag: nil,
            role: .trainee,
            hairStyleId: PixelHairArt.style(id: look.hairStyleId).id,
            accessoryId: PixelHairArt.accessory(id: look.accessoryId).id,
            gender: look.genderValue
        )
    }
}
