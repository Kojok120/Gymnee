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
                    Text("遠征で持ち帰った装備を着せ替えられます。見た目だけで、強さは変わりません。")
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
