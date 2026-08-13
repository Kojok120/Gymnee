import SwiftUI

/// 育成タブの初回案内。
///
/// この画面は説明文をほぼ持たない作りなので、**遊び方はここで一度だけ伝える**。
/// 伝えるのは 4 つだけ: 筋トレでテストステロンパワーが貯まること、それが遠征の燃料になること、
/// 床の物は拾えること、キャラを押すとからだが見られること。
/// そして強くなるのは現実のトレーニングだけであること。
///
/// 表示は 1 回きり（`hasSeenKey`）。設定に出すほどのものではないので、再表示の導線は持たない。
struct CharacterOnboardingSheet: View {
    /// 一度見たら二度と出さないための保存キー。
    static let hasSeenKey = "gymnee.character.onboarded"

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.sm) {
                Text("ここはキャラの部屋")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("あなたが積み上げた記録が、そのまま姿になる")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                row(
                    sprite: PixelCharacterArt.dumbbell,
                    accent: Color(hexF: 0xC6FF3D),
                    title: "筋トレするとテストステロンパワーが貯まる",
                    detail: "記録した分だけ増える。アプリの中で増やす方法は無い"
                )
                row(
                    sprite: PixelItemArt.course(id: "morning-hill"),
                    accent: Theme.info,
                    title: "パワーを使って遠征に送り出す",
                    detail: "ドアから出かけて、時間が経つとおみやげを持って帰る"
                )
                row(
                    sprite: PixelItemArt.pickup(id: "creatine"),
                    accent: Color(hexF: 0xE8563F),
                    title: "床に落ちた物はなぞって拾える",
                    detail: "前の週に目標を達成していると、落ちやすくなる"
                )
                row(
                    sprite: PixelCharacterArt.mirror,
                    accent: Theme.series2,
                    title: "キャラをタップするとからだが見られる",
                    detail: "今週どこを鍛えたか、どこが回復したかが人体図で分かる"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("強くなるのは現実のトレーニングだけ。ここでは装備と見た目しか手に入らない。")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            Button("はじめる") { dismiss() }
                .buttonStyle(.gymneePrimary(fullWidth: true))
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.bg0)
        .presentationDetents([.large])
    }

    private func row(sprite: PixelSprite, accent: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            PixelSpriteView(sprite: sprite, palette: palette(accent: accent), side: 44)
                .frame(width: 52, height: 52)
                .background(Theme.bg2, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func palette(accent: Color) -> PixelPalette {
        var palette = PixelPalette.neutral
        palette.accent = accent
        return palette
    }
}
