import SwiftUI

/// 育成タブの初回案内。
///
/// この画面は説明文をほぼ持たない作りなので、**遊び方はここで一度だけ伝える**。
/// 伝えるのは 4 つだけ: 筋トレでテストステロンパワーが貯まること、それが遠征の燃料になること、
/// 床の物は拾えること、キャラを押すとからだが見られること。
/// そして強くなるのは現実のトレーニングだけであること。
///
/// 表示は 1 回きり（`hasSeenKey`）。設定に出すほどのものではないので、再表示の導線は持たない。
///
/// 最初にキャラの性別を選ばせる（issue #141）。選んだ瞬間に保存し、あとから「見た目」でも変えられる。
/// 項目が増えて小さい端末では収まらないので、本文はスクロールさせ「はじめる」だけ下に固定する。
struct CharacterOnboardingSheet: View {
    /// 一度見たら二度と出さないための保存キー。
    static let hasSeenKey = "gymnee.character.onboarded"

    /// 見本に使ういまの体格・色・髪型（記録が無ければ最小の体格）。
    let build: CharacterBuild
    let skin: CharacterSkin
    let currentHairId: String
    let gender: CharacterGender
    let onChooseGender: (CharacterGender) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .padding(Theme.Spacing.xl)
            }
            Button("はじめる") { dismiss() }
                .buttonStyle(.gymneePrimary(fullWidth: true))
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
        }
        .background(Theme.bg0)
        .presentationDetents([.large])
    }

    private var content: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.sm) {
                Text("ここはキャラの部屋")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("あなたが積み上げた記録が、そのまま姿になります")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            genderPicker

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                row(
                    sprite: PixelCharacterArt.dumbbell,
                    accent: Color(hexF: 0xC6FF3D),
                    title: "筋トレするとテストステロンパワーが貯まります",
                    detail: "記録した分だけ増えます。あとは床の拾い物で少し足せるだけです"
                )
                row(
                    sprite: PixelBossArt.slime,
                    accent: Color(hexF: 0x8BC34A),
                    title: "毎週のボスを友達と倒します",
                    detail: "トレーニング1回が1撃。下の赤い「ボスに挑む」から、1人でも友達とでも挑めます"
                )
                row(
                    sprite: PixelItemArt.course(id: "morning-hill"),
                    accent: Theme.info,
                    title: "パワーを使って遠征に送り出せます",
                    detail: "ドアから出かけて、時間が経つとおみやげを持って帰ります"
                )
                row(
                    sprite: PixelItemArt.pickup(id: "creatine"),
                    accent: Color(hexF: 0xE8563F),
                    title: "床に落ちた物はなぞって拾えます",
                    detail: "前の週に目標を達成していると、落ちやすくなります"
                )
                row(
                    sprite: PixelCharacterArt.mirror,
                    accent: Theme.series2,
                    title: "キャラをタップするとからだが見られます",
                    detail: "今週どこを鍛えたか、どこが回復したかが人体図で分かります"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("強くなるのは現実のトレーニングだけです。ここで手に入るのは装備と見た目、トロフィー、それに少しのパワーだけです。")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    /// 性別の選択。見本は選んだときに合わせる髪型で描く（女性ならボブ）。
    private var genderPicker: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(CharacterGender.allCases) { option in
                    Button { onChooseGender(option) } label: {
                        VStack(spacing: Theme.Spacing.xs) {
                            PixelCharacterFigure(look: PixelCharacterRenderer.Look(
                                build: build, skin: skin, equipped: [:], stage: .rookie,
                                carriesPack: false, nameTag: nil, role: .trainee,
                                hairStyleId: CharacterGender.hairAfterChoosing(option, current: currentHairId),
                                gender: option
                            ))
                            .frame(width: 64, height: 78)
                            Text(option.label)
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .gymneeCard(padding: Theme.Spacing.md, highlighted: option == gender)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == gender ? .isSelected : [])
                }
            }
            Text("あとから「見た目」でいつでも変えられます")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
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
