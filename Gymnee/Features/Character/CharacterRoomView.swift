import SwiftUI
import SwiftData

/// 「育成」タブ＝キャラの部屋。
///
/// トレーニングを自分キャラの育成として見せる画面。**現実だけがエンジン**で、
/// レベル・進化段階・ステータス・元気はすべて完了ワークアウトから導出する（保存された状態を持たない）。
/// アプリ内でできるのは、貯まった元気を使ってキャラを遠征に送り出し、見た目の装備を集めることだけ。
struct CharacterRoomView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal = 3

    @Query private var completedWorkouts: [Workout]
    @Query private var records: [PersonalRecord]
    @Query private var runs: [ExpeditionRun]
    @Query private var loadouts: [CharacterLoadout]
    /// 合トレ判定用：フォロー中の人の投稿（自分以外）。
    @Query private var feedItems: [FeedItem]

    /// 受け取り演出中の戦利品（道中の出来事つき）。
    @State private var celebrating: ClaimResult?
    @State private var showOutfit = false
    @State private var showSkins = false

    init(userId: UUID) {
        self.userId = userId
        _completedWorkouts = Query(filter: #Predicate<Workout> { $0.userId == userId && $0.completedAt != nil })
        _records = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId })
        _runs = Query(
            filter: #Predicate<ExpeditionRun> { $0.userId == userId },
            sort: [SortDescriptor(\ExpeditionRun.startedAt, order: .reverse)]
        )
        _loadouts = Query(filter: #Predicate<CharacterLoadout> { $0.userId == userId })
        _feedItems = Query(filter: #Predicate<FeedItem> { $0.userId != userId })
    }

    /// 受け取り結果（祝福シートに渡す）。
    struct ClaimResult: Identifiable {
        let item: Expedition.Item
        let events: [ExpeditionJourney.Event]
        let coop: Bool
        var id: String { item.id }
    }

    // MARK: - 導出（すべて現実の記録から）

    private var sessions: [CharacterProgress.SessionInput] {
        CharacterInputs.sessions(
            from: completedWorkouts,
            prCountByWorkout: CharacterInputs.prCountByWorkout(records)
        )
    }

    private var level: CharacterProgress.Level {
        CharacterProgress.level(totalExperience: CharacterProgress.totalExperience(sessions: sessions))
    }

    private var weeklyStreakWeeks: Int {
        StreakCalculator.currentWeeklyStreak(
            activeDays: completedWorkouts.map { $0.completedAt ?? $0.date },
            weeklyGoal: weeklyGoal
        ).weeks
    }

    private var stage: CharacterProgress.Stage {
        CharacterProgress.stage(level: level.value, prCount: records.count, weeklyStreakWeeks: weeklyStreakWeeks)
    }

    private var nextStage: CharacterProgress.NextStage? {
        CharacterProgress.nextStage(level: level.value, prCount: records.count, weeklyStreakWeeks: weeklyStreakWeeks)
    }

    private var stats: [CharacterProgress.Axis: Int] {
        CharacterProgress.stats(volumeByMuscle: CharacterInputs.volumeByMuscle(from: completedWorkouts))
    }

    private var availableEnergy: Int {
        Expedition.availableEnergy(sessions: sessions, spent: runs.reduce(0) { $0 + $1.energySpent })
    }

    /// 進行中または受け取り待ちの遠征（同時に 1 本まで）。
    private var activeRun: ExpeditionRun? {
        runs.first { !$0.isClaimed }
    }

    /// 受け取り済みの戦利品（新しい順）。
    private var collection: [(run: ExpeditionRun, item: Expedition.Item)] {
        runs.compactMap { run in run.reward.map { (run, $0) } }
    }

    /// 持っている装備の id。
    private var ownedItemIds: Set<String> {
        Set(runs.compactMap(\.rewardItemId))
    }

    /// 見た目の状態（無ければ既定値。保存は必要になった時だけ作る）。
    private var loadout: CharacterLoadout? { loadouts.first }

    private var skin: CharacterSkin { SkinCatalog.skin(id: loadout?.skinId) }

    private var equipped: [Expedition.Slot: Expedition.Item] {
        CharacterOutfit.resolve(loadout: loadout?.loadout ?? [:], owned: ownedItemIds)
    }

    private var appearance: CharacterAppearance {
        CharacterAppearance.make(stats: stats, stage: stage)
    }

    /// 今日いっしょに記録した仲間（合トレ）。フォロー中の人の今日の投稿から拾う。
    private var coopPartners: [String] {
        CoopDetector.partnersToday(feedItems: feedItems)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    heroCard
                    if sessions.isEmpty {
                        startPrompt
                    } else {
                        statsSection
                        ExpeditionSection(
                            level: level.value,
                            availableEnergy: availableEnergy,
                            activeRun: activeRun,
                            coopPartners: coopPartners,
                            onStart: start(_:),
                            onClaim: claim(_:)
                        )
                        collectionSection
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("育成")
            .sheet(item: $celebrating) { result in
                RewardCelebrationView(result: result)
            }
            .sheet(isPresented: $showOutfit) {
                OutfitSheet(owned: ownedItemIds, equipped: equipped) { slot, itemId in
                    equip(itemId, in: slot)
                }
            }
            .sheet(isPresented: $showSkins) {
                SkinShopSheet(
                    currentSkinId: skin.id,
                    purchased: loadout?.purchasedSkins ?? [],
                    onSelect: { selectSkin($0) },
                    onPurchase: { purchaseSkin($0) }
                )
            }
        }
    }

    // MARK: - ヒーロー（レベルと進化）

    private var heroCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                // レベル進捗のリングをキャラの背後に回す。
                Circle()
                    .stroke(Theme.bg3, lineWidth: 6)
                    .frame(width: 214, height: 214)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, level.progress)))
                    .stroke(Theme.streakRing, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 214, height: 214)
                CharacterFigureView(appearance: appearance, stage: stage, skin: skin, equipped: equipped, size: 200)
            }
            .frame(height: 220)

            Text(stage.title)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: Theme.Spacing.sm) {
                Text("Lv.\(level.value)").font(.numM).foregroundStyle(Theme.lime)
                if level.expForNextLevel > 0 {
                    Text("\(level.expIntoLevel) / \(level.expForNextLevel) EXP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let next = nextStage {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("次の進化: \(next.stage.title)")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.textSecondary)
                    if next.unmet.isEmpty {
                        Text("条件達成。次の記録で進化する")
                            .font(.caption2)
                            .foregroundStyle(Theme.lime)
                    } else {
                        Text(next.unmet.joined(separator: " / "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button { showOutfit = true } label: {
                    Label("着替え", systemImage: "tshirt.fill")
                }
                .buttonStyle(.gymneeSecondary)
                .disabled(ownedItemIds.isEmpty)
                .opacity(ownedItemIds.isEmpty ? 0.4 : 1)

                Button { showSkins = true } label: {
                    Label("スキン", systemImage: "paintpalette.fill")
                }
                .buttonStyle(.gymneeSecondary)
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .gymneeCard(highlighted: stage >= .veteran)
    }

    private var startPrompt: some View {
        EmptyStateView(
            systemImage: "figure.strengthtraining.traditional",
            title: "まだ何も始まっていない",
            message: "キャラが育つのは現実のトレーニングだけ。1回記録すると動き出す。",
            actionTitle: "記録をはじめる",
            action: { NotificationCenter.default.post(name: .gymneeStartWorkout, object: nil) }
        )
        .padding(.top, Theme.Spacing.xl)
    }

    // MARK: - ステータス（現実の写し）

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "ステータス")
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(CharacterProgress.Axis.allCases, id: \.self) { axis in
                    statRow(axis, value: stats[axis] ?? 0)
                }
            }
            .gymneeCard()
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

    // MARK: - コレクション

    @ViewBuilder
    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "戦利品")
            if collection.isEmpty {
                Text("遠征から持ち帰った装備がここに並ぶ。強さには影響しない、見た目だけの勲章。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gymneeCard()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.sm) {
                    ForEach(collection, id: \.run.id) { entry in
                        lootTile(entry.item)
                    }
                }
            }
        }
    }

    private func lootTile(_ item: Expedition.Item) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: item.symbol)
                .font(.title2)
                .foregroundStyle(rarityColor(item.rarity))
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
                .strokeBorder(rarityColor(item.rarity).opacity(item.rarity == .common ? 0 : 0.5), lineWidth: 1)
        }
    }

    private func rarityColor(_ rarity: Expedition.Rarity) -> Color {
        switch rarity {
        case .common: return Theme.textSecondary
        case .rare: return Theme.info
        case .epic: return Theme.warning
        }
    }

    // MARK: - 操作

    /// 遠征に送り出す。元気は `ExpeditionRun.energySpent` の合計として引かれる。
    private func start(_ course: Expedition.Course) {
        guard activeRun == nil,
              level.value >= course.minLevel,
              availableEnergy >= course.energyCost else { return }
        let startedAt = Date.now
        context.insert(
            ExpeditionRun(
                userId: userId,
                courseId: course.id,
                startedAt: startedAt,
                finishesAt: Expedition.finishDate(startedAt: startedAt, course: course),
                energySpent: course.energyCost
            )
        )
        try? context.save()
    }

    /// 帰還した遠征の報酬を受け取る。抽選は遠征 id をシードにした決定的抽選。
    /// 空いている部位、または今より良いものが出たときは自動で着せる（持ち帰ったら姿が変わる）。
    private func claim(_ run: ExpeditionRun) {
        guard run.isAwaitingClaim(asOf: .now) else { return }
        let coop = !coopPartners.isEmpty
        let item = Expedition.reward(courseId: run.courseId, seed: run.id, coop: coop)
        run.rewardItemId = item.id
        run.claimedAt = .now

        let state = ensureLoadout()
        if CharacterOutfit.shouldAutoEquip(item, current: equipped[item.slot]) {
            state.setItem(item.id, for: item.slot)
        }
        try? context.save()

        celebrating = ClaimResult(
            item: item,
            events: ExpeditionJourney.events(courseId: run.courseId, seed: run.id, coop: coop),
            coop: coop
        )
    }

    private func equip(_ itemId: String?, in slot: Expedition.Slot) {
        let state = ensureLoadout()
        state.setItem(itemId, for: slot)
        try? context.save()
    }

    private func selectSkin(_ id: String) {
        let state = ensureLoadout()
        state.skinId = id
        state.updatedAt = .now
        try? context.save()
    }

    /// スキン購入。**課金は未接続のダミー**で、押した時点で所持扱いにする。
    private func purchaseSkin(_ skin: CharacterSkin) {
        let state = ensureLoadout()
        state.addPurchasedSkin(skin.id)
        state.skinId = skin.id
        try? context.save()
    }

    /// 見た目の保存先を必要になった時に作る。
    private func ensureLoadout() -> CharacterLoadout {
        if let existing = loadout { return existing }
        let created = CharacterLoadout(userId: userId)
        context.insert(created)
        return created
    }
}

/// 受け取り演出。道中に何が起きたかを見せてから戦利品を渡す（送って待つだけにしないため）。
private struct RewardCelebrationView: View {
    let result: CharacterRoomView.ClaimResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: result.item.symbol)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Theme.lime)
                    .padding(Theme.Spacing.lg)
                    .background(Theme.limeSoft, in: Circle())

                VStack(spacing: Theme.Spacing.xs) {
                    Text(result.item.rarity.label)
                        .font(.overline)
                        .foregroundStyle(Theme.textTertiary)
                    Text(result.item.name)
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(result.item.slot.label)に装備できる")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: result.coop ? "道中（共闘）" : "道中")
                    ForEach(result.events) { event in
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            Image(systemName: event.symbol)
                                .font(.subheadline)
                                .foregroundStyle(event.isGood ? Theme.lime : Theme.textTertiary)
                                .frame(width: 22)
                            Text(event.text)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .gymneeCard()

                Button("閉じる") { dismiss() }
                    .buttonStyle(.gymneePrimary(fullWidth: true))
            }
            .padding(Theme.Spacing.xl)
        }
        .background(Theme.bg0)
    }
}
