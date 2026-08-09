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

    /// 受け取り演出中の戦利品。
    @State private var celebrating: Expedition.Item?

    init(userId: UUID) {
        self.userId = userId
        _completedWorkouts = Query(filter: #Predicate<Workout> { $0.userId == userId && $0.completedAt != nil })
        _records = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId })
        _runs = Query(
            filter: #Predicate<ExpeditionRun> { $0.userId == userId },
            sort: [SortDescriptor(\ExpeditionRun.startedAt, order: .reverse)]
        )
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
            .sheet(item: $celebrating) { item in
                RewardCelebrationView(item: item)
                    .presentationDetents([.height(360)])
            }
        }
    }

    // MARK: - ヒーロー（レベルと進化）

    private var heroCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            CharacterAvatarView(stage: stage, levelProgress: level.progress)

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
    private func claim(_ run: ExpeditionRun) {
        guard run.isAwaitingClaim(asOf: .now) else { return }
        let item = Expedition.reward(courseId: run.courseId, seed: run.id)
        run.rewardItemId = item.id
        run.claimedAt = .now
        try? context.save()
        celebrating = item
    }
}

/// 受け取り演出。PR ほどの祝祭ではないが、手に入った瞬間はきちんと見せる。
private struct RewardCelebrationView: View {
    let item: Expedition.Item
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: item.symbol)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Theme.lime)
                .padding(Theme.Spacing.xl)
                .background(Theme.limeSoft, in: Circle())
            VStack(spacing: Theme.Spacing.xs) {
                Text(item.rarity.label)
                    .font(.overline)
                    .foregroundStyle(Theme.textTertiary)
                Text(item.name)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
            }
            Button("閉じる") { dismiss() }
                .buttonStyle(.gymneePrimary(fullWidth: true))
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg0)
    }
}
