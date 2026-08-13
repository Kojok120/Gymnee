import SwiftUI
import SwiftData

/// 今日のクエスト（＝コーチが組んだ今日のメニュー）。
///
/// コーチとの会話で「クエストにする」を押したあと、**それを確かめる場所がどこにも無かった**。
/// 遠征は部屋のドアから辿れるので、下部ボタンの「遠征」をこの画面に置き換えている。
///
/// 中身は `PlannedWorkout`（記録タブの「今日の計画」と同じ実体）。
/// ここから始めても記録タブから始めても同じ 1 件で、二重に報酬は出ない。
struct QuestSheet: View {
    let userId: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query private var plans: [PlannedWorkout]

    /// コーチを開く（クエストが無いときの導線）。
    let onOpenCoach: () -> Void

    init(userId: UUID, onOpenCoach: @escaping () -> Void) {
        self.userId = userId
        self.onOpenCoach = onOpenCoach
        _plans = Query(
            filter: #Predicate<PlannedWorkout> { $0.userId == userId && !$0.isDone },
            sort: [SortDescriptor(\PlannedWorkout.date, order: .forward)]
        )
    }

    /// 今日ぶんのクエスト。
    private var today: PlannedWorkout? {
        let calendar = Calendar.current
        return plans.first { calendar.isDate($0.date, inSameDayAs: .now) }
    }

    /// 明日以降に控えているもの。
    private var upcoming: [PlannedWorkout] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        return plans.filter { $0.date >= calendar.date(byAdding: .day, value: 1, to: start) ?? start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let today {
                        questCard(today)
                    } else {
                        emptyState
                    }

                    if !upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            SectionHeader(title: "この先の予定")
                            ForEach(upcoming) { plan in
                                upcomingRow(plan)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("クエスト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 今日のクエスト

    private func questCard(_ plan: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                CoachFace(side: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日のクエスト")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(plan.title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
            }

            let lines = exerciseLines(plan)
            if lines.isEmpty {
                Text("種目はまだ決まっていません。コーチに相談すると組んでくれます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            Button("このメニューで記録をはじめる") {
                // 記録タブの「今日の計画」と同じ実体を開く。二重の報酬は作らない。
                NotificationCenter.default.post(name: .gymneeStartWorkout, object: nil)
                dismiss()
            }
            .buttonStyle(.gymneePrimary(fullWidth: true))

            Button("やめておく") {
                context.delete(plan)
                try? context.save()
            }
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard(highlighted: true)
    }

    private func upcomingRow(_ plan: PlannedWorkout) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(plan.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 56, alignment: .leading)
            Text(plan.title)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard(padding: Theme.Spacing.md)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                CoachFace(side: 40)
                Text("今日のクエストはまだ無い")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            Text("コーチに相談すると、今日のメニューを組んでくれます。決まったものはここに並びます。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("コーチに相談する") {
                dismiss()
                onOpenCoach()
            }
            .buttonStyle(.gymneePrimary(fullWidth: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard()
    }

    /// 計画の中身（`detailJSON`）を人が読める行にする。
    private func exerciseLines(_ plan: PlannedWorkout) -> [String] {
        guard let json = plan.detailJSON,
              let data = json.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return items.map { item in
            let name = item["name"] as? String ?? "種目"
            let sets = item["sets"] as? Int ?? 3
            let reps = item["reps"] as? Int ?? 10
            let weight = (item["weightKg"] as? Double).map { Int($0.isFinite ? $0.rounded() : 0) }
                ?? (item["weightKg"] as? Int) ?? 0
            return weight > 0
                ? "・\(name) \(weight)kg × \(reps) × \(sets)セット"
                : "・\(name) \(reps)回 × \(sets)セット"
        }
    }
}
