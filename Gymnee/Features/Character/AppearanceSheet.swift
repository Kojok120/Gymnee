import SwiftUI

/// 見た目の着せ替え（色 / 髪型 / アクセサリー）。
///
/// 旧「スキン」シートを置き換える。売るのは見た目だけという原則は変わらない
/// （強さ・進化・ステータスには一切影響しない）。
///
/// **選んだ結果が即座にプレビューに出る**ことを最優先にした。色だけの丸を並べても
/// 着たときの姿が想像できず、買う理由も選ぶ理由も生まれないため。
struct AppearanceSheet: View {
    let build: CharacterBuild
    let stage: CharacterProgress.Stage
    let equipped: [Expedition.Slot: Expedition.Item]

    let currentSkinId: String
    let currentHairId: String
    let currentAccessoryId: String
    /// 購入済み（スキンと、髪型・アクセサリー）。
    let purchasedSkins: Set<String>
    let purchasedAppearances: Set<String>

    let onSelectSkin: (String) -> Void
    let onSelectHair: (String) -> Void
    let onSelectAccessory: (String) -> Void
    /// 購入（課金は未接続のダミー）。id を所持済みにする。
    let onPurchase: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.hair

    enum Tab: String, CaseIterable, Identifiable {
        case color, hair, accessory
        var id: String { rawValue }
        var title: String {
            switch self {
            case .color: return "色"
            case .hair: return "髪型"
            case .accessory: return "アクセサリー"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.sm)

                ScrollView {
                    VStack(spacing: Theme.Spacing.sm) {
                        switch tab {
                        case .color: colorRows
                        case .hair: hairRows
                        case .accessory: accessoryRows
                        }
                        Text("売るのは見た目だけ。強さは現実のトレーニングでしか手に入らない。")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.top, Theme.Spacing.md)
                        Label("課金は未接続。購入ボタンは動作確認用のダミーです。", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .gymneeCard(padding: Theme.Spacing.md)
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
            .background(Theme.bg0)
            .navigationTitle("見た目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } } }
        }
    }

    // MARK: - プレビュー

    /// いまの選択で実際に描いた姿。正面と横を並べ、髪型の違いが分かるようにする。
    private var preview: some View {
        HStack(spacing: Theme.Spacing.xl) {
            previewFigure(facing: .down)
            previewFigure(facing: .right)
            previewFigure(facing: .up)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .background(Theme.bg1)
    }

    private func previewFigure(facing: CharacterScene.Facing) -> some View {
        Canvas { context, size in
            let dot = max(1, (size.height / CGFloat(PixelCharacterArt.canvasHeight)).rounded(.down))
            PixelCharacterRenderer.draw(
                in: &context,
                look: PixelCharacterRenderer.Look(
                    build: build,
                    skin: SkinCatalog.skin(id: currentSkinId),
                    equipped: equipped,
                    stage: stage,
                    carriesPack: false,
                    nameTag: nil,
                    role: .trainee,
                    hairStyleId: currentHairId,
                    accessoryId: currentAccessoryId
                ),
                frame: .standing,
                facing: facing,
                feet: CGPoint(x: size.width / 2, y: size.height - dot * 2),
                dot: dot
            )
        }
        .frame(width: 84, height: 110)
    }

    // MARK: - 一覧

    private var colorRows: some View {
        ForEach(SkinCatalog.all) { skin in
            row(
                id: skin.id,
                name: skin.name,
                owned: SkinCatalog.isOwned(skin, purchased: purchasedSkins),
                isCurrent: skin.id == currentSkinId,
                priceLabel: skin.priceLabel,
                select: { onSelectSkin(skin.id) }
            ) {
                ZStack {
                    Circle().fill(Color(hexF: skin.bodyHex)).frame(width: 36, height: 36)
                    Circle().fill(Color(hexF: skin.accentHex)).frame(width: 18, height: 18).offset(x: 10, y: 10)
                }
            }
        }
    }

    private var hairRows: some View {
        ForEach(PixelHairArt.styles) { style in
            row(
                id: style.id,
                name: style.name,
                owned: PixelHairArt.isOwned(style, purchased: purchasedAppearances),
                isCurrent: style.id == currentHairId,
                priceLabel: style.priceLabel,
                select: { onSelectHair(style.id) }
            ) {
                headThumbnail(hairId: style.id, accessoryId: "none")
            }
        }
    }

    private var accessoryRows: some View {
        ForEach(PixelHairArt.accessories) { accessory in
            row(
                id: accessory.id,
                name: accessory.name,
                owned: PixelHairArt.isOwned(accessory, purchased: purchasedAppearances),
                isCurrent: accessory.id == currentAccessoryId,
                priceLabel: accessory.priceLabel,
                select: { onSelectAccessory(accessory.id) }
            ) {
                headThumbnail(hairId: currentHairId, accessoryId: accessory.id)
            }
        }
    }

    /// 一覧の見本は**顔だけ**を描く。全身だと髪型の差が小さくて選べない。
    private func headThumbnail(hairId: String, accessoryId: String) -> some View {
        Canvas { context, size in
            let sprite = PixelHairArt.headBaseFront
            let dot = max(1, (size.width / CGFloat(sprite.width)).rounded(.down))
            let origin = CGPoint(
                x: ((size.width - CGFloat(sprite.width) * dot) / 2).rounded(),
                y: ((size.height - CGFloat(sprite.height) * dot) / 2).rounded()
            )
            let palette = PixelPalette.make(skin: SkinCatalog.skin(id: currentSkinId))
            context.drawPixels(sprite, at: origin, dot: dot, palette: palette)
            context.drawPixels(PixelHairArt.hair(styleId: hairId, facing: .down), at: origin, dot: dot, palette: palette)
            if let accessory = PixelHairArt.accessorySprite(id: accessoryId, facing: .down) {
                context.drawPixels(accessory, at: origin, dot: dot, palette: palette)
            }
        }
        .frame(width: 42, height: 40)
    }

    private func row<Thumb: View>(
        id: String,
        name: String,
        owned: Bool,
        isCurrent: Bool,
        priceLabel: String,
        select: @escaping () -> Void,
        @ViewBuilder thumbnail: () -> Thumb
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            thumbnail()
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Text(owned ? (isCurrent ? "使用中" : "所持済み") : priceLabel)
                    .font(.caption)
                    .foregroundStyle(isCurrent ? Theme.lime : .secondary)
            }
            Spacer()
            if owned {
                Button(isCurrent ? "使用中" : "着る", action: select)
                    .buttonStyle(.gymneeSecondary)
                    .disabled(isCurrent)
                    .opacity(isCurrent ? 0.5 : 1)
            } else {
                Button("購入") { onPurchase(id) }
                    .buttonStyle(.gymneeSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard(padding: Theme.Spacing.md, highlighted: isCurrent)
    }
}
