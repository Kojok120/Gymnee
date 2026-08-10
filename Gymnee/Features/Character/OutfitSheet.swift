import SwiftUI

/// 着替えシート。持ち帰った装備を部位ごとに着け替える。
/// 装備で強さは変わらないことを画面上でも明示する（課金で強さを売らない設計の一部）。
struct OutfitSheet: View {
    let owned: Set<String>
    let equipped: [Expedition.Slot: Expedition.Item]
    let onEquip: (Expedition.Slot, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    Text("遠征で持ち帰った装備を着せ替えられる。見た目だけで、強さは変わらない。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Expedition.Slot.allCases, id: \.self) { slot in
                        slotSection(slot)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("着替え")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } } }
        }
    }

    @ViewBuilder
    private func slotSection(_ slot: Expedition.Slot) -> some View {
        let candidates = CharacterOutfit.candidates(for: slot, owned: owned)
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: slot.label)
            if candidates.isEmpty {
                Text("まだ持っていない")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gymneeCard(padding: Theme.Spacing.md)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.sm) {
                    noneTile(slot)
                    ForEach(candidates) { item in
                        itemTile(item, slot: slot)
                    }
                }
            }
        }
    }

    private func noneTile(_ slot: Expedition.Slot) -> some View {
        let isSelected = equipped[slot] == nil
        return Button { onEquip(slot, nil) } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "circle.slash").font(.title3).foregroundStyle(Theme.textTertiary)
                Text("なし").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .strokeBorder(isSelected ? Theme.lime : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func itemTile(_ item: Expedition.Item, slot: Expedition.Slot) -> some View {
        let isSelected = equipped[slot]?.id == item.id
        return Button { onEquip(slot, isSelected ? nil : item.id) } label: {
            VStack(spacing: Theme.Spacing.xs) {
                PixelSpriteView(sprite: PixelItemArt.icon(for: item), palette: .item(rarity: item.rarity), side: 40)
                Text(item.name)
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .strokeBorder(isSelected ? Theme.lime : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func rarityColor(_ rarity: Expedition.Rarity) -> Color {
        switch rarity {
        case .common: return Theme.textSecondary
        case .rare: return Theme.info
        case .epic: return Theme.warning
        }
    }
}

/// スキンショップ。**課金は未接続のダミー**で、購入ボタンは即座に所持扱いにする。
/// 売るのは見た目だけ（強さは現実でしか買えない）という原則を画面にも書いておく。
struct SkinShopSheet: View {
    let currentSkinId: String
    let purchased: Set<String>
    let onSelect: (String) -> Void
    let onPurchase: (CharacterSkin) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("売るのは見た目だけ。強さは現実のトレーニングでしか手に入らない。")
                        .font(.caption).foregroundStyle(.secondary)
                    Label("課金は未接続。購入ボタンは動作確認用のダミーです。", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gymneeCard(padding: Theme.Spacing.md)

                    ForEach(SkinCatalog.all) { skin in
                        skinRow(skin)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("スキン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } } }
        }
    }

    private func skinRow(_ skin: CharacterSkin) -> some View {
        let owned = SkinCatalog.isOwned(skin, purchased: purchased)
        let isCurrent = skin.id == currentSkinId
        return HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(Color(hexF: skin.bodyHex)).frame(width: 44, height: 44)
                Circle().fill(Color(hexF: skin.accentHex)).frame(width: 20, height: 20).offset(x: 12, y: 12)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(skin.name).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Text(owned ? (isCurrent ? "使用中" : "所持済み") : skin.priceLabel)
                    .font(.caption).foregroundStyle(isCurrent ? Theme.lime : .secondary)
            }
            Spacer()
            if owned {
                Button(isCurrent ? "使用中" : "着る") { onSelect(skin.id) }
                    .buttonStyle(.gymneeSecondary)
                    .disabled(isCurrent)
                    .opacity(isCurrent ? 0.5 : 1)
            } else {
                Button("購入") { onPurchase(skin) }
                    .buttonStyle(.gymneeSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard(padding: Theme.Spacing.md)
    }
}
