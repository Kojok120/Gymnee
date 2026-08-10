import SwiftUI

/// ステータスと進化条件。シーンから追い出した「数字」はここにまとめる。
struct CharacterStatusSheet: View {
    let level: CharacterProgress.Level
    let stage: CharacterProgress.Stage
    let nextStage: CharacterProgress.NextStage?
    let stats: [CharacterProgress.Axis: Int]
    let streakWeeks: Int
    let sessionCount: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    summary
                    evolution
                    statsSection
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("ステータス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var summary: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.title).font(.headline).foregroundStyle(Theme.lime)
                Text("Lv.\(level.value)").font(.numL).foregroundStyle(Theme.textPrimary)
                if level.expForNextLevel > 0 {
                    Text("\(level.expIntoLevel) / \(level.expForNextLevel) EXP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                StatPill(value: "\(sessionCount)", label: "記録")
                StatPill(value: "\(streakWeeks)週", label: "連続")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard(highlighted: stage >= .veteran)
    }

    @ViewBuilder
    private var evolution: some View {
        if let next = nextStage {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: "次の進化")
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: next.stage.symbol)
                            .font(.subheadline)
                            .foregroundStyle(Theme.lime)
                        Text(next.stage.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    if next.unmet.isEmpty {
                        Text("条件達成。次の記録で進化する")
                            .font(.caption)
                            .foregroundStyle(Theme.lime)
                    } else {
                        ForEach(next.unmet, id: \.self) { requirement in
                            Label(requirement, systemImage: "circle")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Text("進化すると姿が変わり、部屋に器具が増える。")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .gymneeCard()
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "部位別")
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(CharacterProgress.Axis.allCases, id: \.self) { axis in
                    statRow(axis, value: stats[axis] ?? 0)
                }
            }
            .gymneeCard()
            Text("押す力で肩が、腕力で腕が、脚力で脚が太くなる。伸ばした部位がそのまま体型に出る。")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func statRow(_ axis: CharacterProgress.Axis, value: Int) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: axis.symbol)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24)
            Text(axis.label)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 64, alignment: .leading)
            ProgressView(value: Double(value), total: 99)
                .tint(Theme.lime)
            Text("\(value)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

/// 遠征シート。中身は従来の `ExpeditionSection` をそのまま使う。
struct ExpeditionSheet: View {
    let level: Int
    let availableEnergy: Int
    let activeRun: ExpeditionRun?
    let coopPartners: [String]
    let onStart: (Expedition.Course) -> Void
    let onClaim: (ExpeditionRun) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ExpeditionSection(
                    level: level,
                    availableEnergy: availableEnergy,
                    activeRun: activeRun,
                    coopPartners: coopPartners,
                    onStart: onStart,
                    onClaim: onClaim
                )
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("遠征")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 集めた戦利品の一覧。部屋の棚に並んでいるものと同じ。
struct LootCollectionSheet: View {
    let items: [Expedition.Item]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("遠征から持ち帰った装備。強さには影響しない、見た目だけの勲章。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.sm) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            tile(item)
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("戦利品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func tile(_ item: Expedition.Item) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            PixelSpriteView(sprite: PixelItemArt.icon(for: item), palette: .item(rarity: item.rarity), side: 48)
            Text(item.name)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(
                    PixelCharacterRenderer.rarityColor(item.rarity).opacity(item.rarity == .common ? 0 : 0.5),
                    lineWidth: 1
                )
        }
    }
}
