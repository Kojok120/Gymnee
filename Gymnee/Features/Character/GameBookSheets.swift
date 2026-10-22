import SwiftUI

// issue #155 で足した育成タブの 3 枚: 技図鑑・冒険マップ・称号。
// 中身はすべて記録から導出した値を受け取って描くだけ（数え方は Core/Domain の純粋関数）。

// MARK: - 技図鑑

/// 技図鑑。種目ごとの技と、そのレベル・威力。まだ覚えていないプリセットの技は「？？？」で、何で覚えるかを見せる。
struct TechniqueBookSheet: View {
    let book: [Technique.Entry]

    @Environment(\.dismiss) private var dismiss

    private var groups: [(muscle: MuscleGroup, entries: [Technique.Entry])] {
        MuscleGroup.allCases.compactMap { muscle in
            let entries = book.filter { $0.muscle == muscle }
            return entries.isEmpty ? nil : (muscle, entries)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    summary
                    ForEach(groups, id: \.muscle) { group in
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            SectionHeader(title: group.muscle.label)
                            ForEach(group.entries) { entry in
                                row(entry)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("技図鑑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } } }
        }
    }

    private var summary: some View {
        let learned = Technique.learnedCount(book)
        let presets = book.filter(\.isPreset).count
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("覚えた技 \(learned) / \(presets)")
                .font(.pixel(size: 20, relativeTo: .title3))
                .foregroundStyle(Theme.textPrimary)
            Text("初めての種目で技を覚え、セットを重ねると技のレベルが上がります。自己ベストで威力が上がります。")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard()
    }

    private func row(_ entry: Technique.Entry) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(entry.isLearned ? Theme.muscleColor(entry.muscle) : Theme.textTertiary.opacity(0.3))
                .frame(width: 6, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isLearned ? entry.techniqueName : "？？？")
                    .font(.pixel(size: 15, relativeTo: .subheadline))
                    .foregroundStyle(entry.isLearned ? Theme.textPrimary : Theme.textTertiary)
                Text(entry.isLearned ? entry.exerciseName : "\(entry.exerciseName)で覚える")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                if entry.isLearned, let next = Technique.setsToNextLevel(sets: entry.sets) {
                    Text("次のレベルまで あと\(next)セット")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            if entry.isLearned {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Lv.\(entry.level)")
                        .font(.pixel(size: 15, relativeTo: .subheadline))
                        .foregroundStyle(Theme.lime)
                    Text("威力 \(entry.power)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard(padding: Theme.Spacing.md)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 冒険マップ

/// 冒険マップ。1 回記録すると 1 マス進む。地方ごとにマスを並べ、いまの位置に主人公を立たせる。
struct AdventureMapSheet: View {
    let completedWorkouts: Int
    let look: PixelCharacterRenderer.Look

    @Environment(\.dismiss) private var dismiss

    private var position: AdventureMap.Position { AdventureMap.position(completedWorkouts: completedWorkouts) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        header
                        ForEach(Array(AdventureMap.regions.enumerated()), id: \.offset) { index, region in
                            regionCard(index: index, region: region)
                                .id(index)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
                .onAppear { proxy.scrollTo(position.regionIndex, anchor: .center) }
            }
            .background(Theme.bg0)
            .navigationTitle("冒険マップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } } }
        }
    }

    private var header: some View {
        let next = AdventureMap.nextEncounter(from: position)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(position.lap > 1 ? "\(position.lap)周目 · \(position.region.name)" : position.region.name)
                .font(.pixel(size: 20, relativeTo: .title3))
                .foregroundStyle(Theme.textPrimary)
            Text(encounterText(next))
                .font(.subheadline.bold())
                .foregroundStyle(Theme.lime)
            Text("ワークアウトを 1 回記録するたびに 1 マス進みます。重さや回数ではなく、通った回数で進みます。")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard()
    }

    private func encounterText(_ next: (node: AdventureMap.Node, remaining: Int)) -> String {
        switch next.node {
        case .regionBoss(let bossId):
            return "あと\(next.remaining)回で 大ボス「\(PartyBoss.boss(id: bossId)?.name ?? "ボス")」"
        case .midBoss(let bossId):
            return "あと\(next.remaining)回で 中ボス「\(PartyBoss.boss(id: bossId)?.name ?? "ボス")」"
        case .path:
            return "あと\(next.remaining)回で 次の山場"
        }
    }

    private func regionCard(index: Int, region: AdventureMap.Region) -> some View {
        let state = regionState(index)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                PixelSpriteView(sprite: PixelItemArt.course(id: region.id), palette: .neutral, side: 32)
                    .opacity(state == .locked ? 0.35 : 1)
                Text(region.name)
                    .font(.pixel(size: 16, relativeTo: .headline))
                    .foregroundStyle(state == .locked ? Theme.textTertiary : Theme.textPrimary)
                Spacer()
                Text(state == .cleared ? "突破" : (state == .current ? "\(position.step) / \(region.steps)" : "未到達"))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(state == .cleared ? Theme.lime : Theme.textSecondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(1...region.steps, id: \.self) { step in
                    cell(regionIndex: index, step: step, state: state)
                }
            }
        }
        .gymneeCard(padding: Theme.Spacing.md, highlighted: state == .current)
    }

    private enum RegionState { case cleared, current, locked }

    private func regionState(_ index: Int) -> RegionState {
        if index < position.regionIndex { return .cleared }
        if index == position.regionIndex { return .current }
        return .locked
    }

    @ViewBuilder
    private func cell(regionIndex: Int, step: Int, state: RegionState) -> some View {
        let passed = state == .cleared || (state == .current && step <= position.step)
        let here = state == .current && step == position.step + 1
        let node = AdventureMap.node(regionIndex: regionIndex, step: step)
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(passed ? Theme.lime.opacity(0.22) : Theme.bg2)
            switch node {
            case .path:
                if passed {
                    Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(Theme.lime)
                } else {
                    Circle().fill(Theme.textTertiary.opacity(0.4)).frame(width: 5, height: 5)
                }
            case .midBoss(let bossId):
                bossIcon(bossId, tier: .weak, passed: passed, reached: passed || here, side: 26)
            case .regionBoss(let bossId):
                bossIcon(bossId, tier: .strong, passed: passed, reached: passed || here, side: 30)
            }
            if here {
                PixelCharacterFigure(look: look)
                    .frame(width: 30, height: 36)
                    .offset(y: -6)
            }
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private func bossIcon(_ bossId: String, tier: PartyBoss.Tier, passed: Bool, reached: Bool, side: CGFloat) -> some View {
        if reached {
            PixelSpriteView(sprite: PixelBossArt.sprite(bossId: bossId, tier: tier),
                            palette: PixelBossArt.palette(bossId: bossId, tier: tier), side: side)
                .opacity(passed ? 0.45 : 1)
        } else {
            PixelSpriteView(sprite: PixelBossArt.sprite(bossId: bossId, tier: tier), palette: Self.silhouette, side: side)
        }
    }

    /// まだ着いていないボスは影だけ見せる（図鑑と同じ）。
    private static let silhouette: PixelPalette = {
        var palette = PixelPalette.neutral
        palette.accent = Color(hexF: 0x3A3F3B)
        palette.accentShade = Color(hexF: 0x2C302D)
        palette.outline = Color(hexF: 0x2C302D)
        palette.light = Color(hexF: 0x3A3F3B)
        palette.eye = Color(hexF: 0x2C302D)
        palette.dark = Color(hexF: 0x2C302D)
        palette.metal = Color(hexF: 0x3A3F3B)
        palette.wood = Color(hexF: 0x3A3F3B)
        palette.cloth = Color(hexF: 0x3A3F3B)
        palette.cheek = Color(hexF: 0x3A3F3B)
        return palette
    }()
}

// MARK: - 称号

/// 称号。手に入れたものから 1 つを着け、フィードの投稿と週ボスのパーティで名前の横に出す。
struct TitleSheet: View {
    let stats: PlayerTitle.Stats
    let selectedId: String?
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    private var wearing: PlayerTitle.Title? { PlayerTitle.resolve(selectedId: selectedId, stats: stats) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    header
                    ForEach(PlayerTitle.catalog) { title in
                        row(title)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("称号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } } }
        }
    }

    private var header: some View {
        let earned = PlayerTitle.earned(stats: stats).count
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(wearing.map { "「\($0.name)」を着けています" } ?? "称号を着けていません")
                .font(.pixel(size: 18, relativeTo: .title3))
                .foregroundStyle(Theme.textPrimary)
            Text("手に入れた称号 \(earned) / \(PlayerTitle.catalog.count)。着けた称号は、フィードの投稿とパーティで名前の横に出ます。")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if wearing != nil {
                Button("称号を外す") { onSelect(nil) }
                    .font(.caption.bold())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard()
    }

    private func row(_ title: PlayerTitle.Title) -> some View {
        let earned = PlayerTitle.isEarned(title, stats: stats)
        let isWearing = wearing?.id == title.id
        let value = min(PlayerTitle.value(of: title, stats: stats), title.target)
        return HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(earned ? title.name : "？？？")
                    .font(.pixel(size: 15, relativeTo: .subheadline))
                    .foregroundStyle(earned ? Theme.textPrimary : Theme.textTertiary)
                Text(title.howTo)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                if !earned && title.target > 1 {
                    ProgressView(value: Double(value), total: Double(title.target))
                        .tint(Theme.lime)
                    Text("\(value) / \(title.target)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            if earned {
                Button(isWearing ? "着けている" : "着ける") { onSelect(title.id) }
                    .buttonStyle(.gymneeSecondary)
                    .disabled(isWearing)
                    .opacity(isWearing ? 0.5 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard(padding: Theme.Spacing.md, highlighted: isWearing)
    }
}
