import SwiftUI

/// ランク込みのボスの絵（issue #133）。強いほど大きく、暗い体に王冠と赤いオーラ。弱いは淡く小さい。
struct BossSpriteView: View {
    let bossId: String
    var tier: PartyBoss.Tier = .medium
    /// 中くらいのときの一辺。弱い・強いはこれを基準に縮める・広げる。
    var side: CGFloat = 144
    var palette: PixelPalette?

    private var scale: CGFloat {
        switch tier {
        case .weak: return 0.75
        case .medium: return 1
        case .strong: return 1.2
        }
    }

    var body: some View {
        ZStack {
            if tier == .strong {
                Circle()
                    .fill(RadialGradient(colors: [Color(hexF: 0xFF3B30).opacity(0.45), .clear],
                                         center: .center, startRadius: 0, endRadius: side * 0.7))
                    .frame(width: side * 1.4, height: side * 1.4)
            }
            PixelSpriteView(
                sprite: PixelBossArt.sprite(bossId: bossId, tier: tier),
                palette: palette ?? PixelBossArt.palette(bossId: bossId, tier: tier),
                side: side * scale
            )
        }
        .frame(height: side * 1.25)
    }
}

/// ランクの印（ボスの名前の横や投票の選択肢に出す）。
struct BossTierBadge: View {
    let tier: PartyBoss.Tier

    var body: some View {
        Text(tier.label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
    }

    private var color: Color {
        switch tier {
        case .weak: return Color(hexF: 0x4FA3D1)
        case .medium: return Color(hexF: 0xD9A23A)
        case .strong: return Color(hexF: 0xD63B3B)
        }
    }
}
