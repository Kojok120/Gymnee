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
    /// 連れているペット id（`PetCatalog.noneId` は連れていない）。
    let currentPetId: String

    /// 所持しているか。StoreKit の所持と、1.4.1 以前のダミー購入の和集合を呼び出し側が解決する。
    /// 種別ごとに id 空間が別なので、Set を渡さずクロージャで引く。
    let isOwned: (StoreCatalog.Kind, String) -> Bool
    /// 表示価格。StoreKit から取れなければ控えの価格、それも出せなければ「—」。
    let priceText: (StoreCatalog.Kind, String) -> String
    /// ストアに繋がっているか。false のときだけ「いまは購入できません」を出す。
    let isStoreReachable: Bool
    /// **その商品を**買えるか。審査状態やストアフロントの対応は商品ごとに違うので、
    /// 全体の可否ではなく 1 件ずつ見る（取れていない商品のボタンを押させない）。
    let canPurchase: (StoreCatalog.Kind, String) -> Bool

    let onSelectSkin: (String) -> Void
    let onSelectHair: (String) -> Void
    let onSelectAccessory: (String) -> Void
    let onSelectPet: (String) -> Void
    /// 購入。成功したら true。
    let onPurchase: (StoreCatalog.Kind, String) async -> Bool
    let onRestore: () async -> Void

    /// 最初に開くタブ。既定は髪型。DEBUG ハーネス（審査用スクリーンショットの撮影）で切り替える。
    var initialTab: Tab = .hair

    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.hair
    /// 購入処理中の product id。押している間は一覧全体を触れなくする。
    @State private var purchasing: String?
    @State private var isRestoring = false

    enum Tab: String, CaseIterable, Identifiable {
        case color, hair, accessory, pet
        var id: String { rawValue }
        var title: String {
            switch self {
            case .color: return "色"
            case .hair: return "髪型"
            case .accessory: return "アクセ"
            case .pet: return "ペット"
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
                        case .pet: petRows
                        }
                        Text("売るのは見た目だけ。強さは現実のトレーニングでしか手に入らない。")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.top, Theme.Spacing.md)

                        if !isStoreReachable {
                            Label("いまは購入できません。通信状況を確かめて、しばらくしてからお試しください。",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.warning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .gymneeCard(padding: Theme.Spacing.md)
                        }

                        Button {
                            Task {
                                isRestoring = true
                                await onRestore()
                                isRestoring = false
                            }
                        } label: {
                            if isRestoring { ProgressView() } else { Text("購入を復元") }
                        }
                        .buttonStyle(.gymneeSecondary)
                        .disabled(isRestoring)
                        .padding(.top, Theme.Spacing.xs)

                        Text("購入した見た目は Apple ID に紐づきます。")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
            .background(Theme.bg0)
            .navigationTitle("見た目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } } }
            .onAppear { tab = initialTab }
        }
    }

    // MARK: - プレビュー

    /// いまの選択で実際に描いた姿。正面と横を並べ、髪型の違いが分かるようにする。
    /// ペットタブでは足元にペットも並べる（連れて歩いたらこう見える、が一目で分かる）。
    private var preview: some View {
        HStack(spacing: Theme.Spacing.xl) {
            previewFigure(facing: .down)
            previewFigure(facing: .right)
            if tab == .pet {
                previewPet
            } else {
                previewFigure(facing: .up)
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .background(Theme.bg1)
    }

    /// 選択中のペット（未選択なら足跡だけ）。キャラと同じ縮尺で並べて大きさの差を見せる。
    @ViewBuilder
    private var previewPet: some View {
        if let pet = PetCatalog.pet(id: currentPetId) {
            Canvas { context, size in
                let dot = max(1, (size.height / CGFloat(PixelCharacterArt.canvasHeight)).rounded(.down))
                let sprite = PixelPetArt.sprite(petId: pet.id, facing: .down, blink: false)
                let origin = CGPoint(
                    x: ((size.width - CGFloat(sprite.width) * dot) / 2).rounded(),
                    y: (size.height - CGFloat(sprite.height) * dot - dot * 2).rounded()
                )
                context.drawPixels(sprite, at: origin, dot: dot, palette: PixelPetArt.palette(petId: pet.id))
            }
            .frame(width: 84, height: 110)
        } else {
            Image(systemName: "pawprint")
                .font(.title2)
                .foregroundStyle(Theme.textTertiary.opacity(0.5))
                .frame(width: 84, height: 110)
        }
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
                kind: .skin,
                id: skin.id,
                name: skin.name,
                owned: !skin.isPaid || isOwned(.skin, skin.id),
                isCurrent: skin.id == currentSkinId,
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
                kind: .hair,
                id: style.id,
                name: style.name,
                owned: !style.isPaid || isOwned(.hair, style.id),
                isCurrent: style.id == currentHairId,
                select: { onSelectHair(style.id) }
            ) {
                headThumbnail(hairId: style.id, accessoryId: "none")
            }
        }
    }

    private var accessoryRows: some View {
        ForEach(PixelHairArt.accessories) { accessory in
            row(
                kind: .accessory,
                id: accessory.id,
                name: accessory.name,
                owned: !accessory.isPaid || isOwned(.accessory, accessory.id),
                isCurrent: accessory.id == currentAccessoryId,
                select: { onSelectAccessory(accessory.id) }
            ) {
                headThumbnail(hairId: currentHairId, accessoryId: accessory.id)
            }
        }
    }

    /// ペットの一覧。未所持でもシルエットにせず普通に描く。
    /// 何が手に入るのか分からないと買う理由が生まれないし、審査用のスクリーンショットにも使えない。
    private var petRows: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // 買ったあと外せないのは不親切なので、「連れていない」を必ず選べるようにする。
            row(
                kind: .pet,
                id: PetCatalog.noneId,
                name: "連れていない",
                owned: true,
                isCurrent: currentPetId == PetCatalog.noneId,
                select: { onSelectPet(PetCatalog.noneId) }
            ) {
                Image(systemName: "nosign")
                    .font(.title3)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 42, height: 40)
            }
            ForEach(PetCatalog.all) { pet in
                row(
                    kind: .pet,
                    id: pet.id,
                    name: pet.name,
                    owned: isOwned(.pet, pet.id),
                    isCurrent: pet.id == currentPetId,
                    select: { onSelectPet(pet.id) }
                ) {
                    petThumbnail(pet.id)
                }
            }
            Text("ペットは見た目だけ。強さにも遠征の結果にも影響しない。")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.Spacing.xs)
        }
    }

    private func petThumbnail(_ petId: String) -> some View {
        Canvas { context, size in
            let sprite = PixelPetArt.sprite(petId: petId, facing: .down, blink: false)
            let dot = max(1, (size.height / CGFloat(PixelPetArt.canvasHeight)).rounded(.down))
            let origin = CGPoint(
                x: ((size.width - CGFloat(sprite.width) * dot) / 2).rounded(),
                y: ((size.height - CGFloat(sprite.height) * dot) / 2).rounded()
            )
            context.drawPixels(sprite, at: origin, dot: dot, palette: PixelPetArt.palette(petId: petId))
        }
        .frame(width: 42, height: 40)
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
        kind: StoreCatalog.Kind,
        id: String,
        name: String,
        owned: Bool,
        isCurrent: Bool,
        select: @escaping () -> Void,
        @ViewBuilder thumbnail: () -> Thumb
    ) -> some View {
        let productID = StoreCatalog.entry(kind: kind, contentID: id)?.productID
        let isPurchasing = purchasing != nil && purchasing == productID
        let buyable = productID != nil && canPurchase(kind, id)
        return HStack(spacing: Theme.Spacing.md) {
            thumbnail()
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Text(owned ? (isCurrent ? "使用中" : "所持済み") : priceText(kind, id))
                    .font(.caption)
                    .foregroundStyle(isCurrent ? Theme.lime : .secondary)
            }
            Spacer()
            if owned {
                Button(isCurrent ? "使用中" : "着る", action: select)
                    .buttonStyle(.gymneeSecondary)
                    .disabled(isCurrent)
                    .opacity(isCurrent ? 0.5 : 1)
            } else if isPurchasing {
                ProgressView()
            } else {
                Button("購入") {
                    guard let productID else { return }
                    Task {
                        purchasing = productID
                        // 買えたらそのまま着せる。買ってから探させない。
                        if await onPurchase(kind, id) { select() }
                        purchasing = nil
                    }
                }
                .buttonStyle(.gymneeSecondary)
                // その商品が取れていない／別の購入が進行中は押させない。
                .disabled(!buyable || purchasing != nil)
                .opacity(buyable ? 1 : 0.45)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard(padding: Theme.Spacing.md, highlighted: isCurrent)
    }
}
