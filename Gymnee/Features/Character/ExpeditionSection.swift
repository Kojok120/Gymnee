import SwiftUI

/// 遠征セクション。元気（現実のトレーニングで貯まる燃料）を払ってキャラを送り出し、
/// 時間が経ったら装備を受け取る。ここでの成果はキャラの強さには一切影響しない。
struct ExpeditionSection: View {
    let level: Int
    let availableEnergy: Int
    /// 進行中または受け取り待ちの遠征（無ければ nil）。
    let activeRun: ExpeditionRun?
    /// 今日いっしょに記録した仲間の名前（合トレ）。空でなければ共闘遠征になる。
    let coopPartners: [String]
    let onStart: (Expedition.Course) -> Void
    let onClaim: (ExpeditionRun) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "遠征")

            energyBar

            if !coopPartners.isEmpty {
                coopBanner
            }

            if let run = activeRun {
                // 残り時間の更新はこのカードだけに閉じ込める（親は全ワークアウトを集計し直すため）。
                TimelineView(.periodic(from: run.startedAt, by: 1)) { context in
                    if run.isAwaitingClaim(asOf: context.date) {
                        claimCard(run)
                    } else {
                        progressCard(run, now: context.date)
                    }
                }
            } else {
                courseList
            }
        }
    }

    // MARK: - 元気

    private var energyBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Label("テストステロンパワー", systemImage: "bolt.heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(availableEnergy)")
                    .font(.numM)
                    .foregroundStyle(Theme.lime)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard()
    }

    /// 合トレ（同じ日に仲間も記録した）が成立していることの告知。
    private var coopBanner: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "person.2.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.lime)
                .frame(width: 32, height: 32)
                .background(Theme.limeSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("今日は\(coopPartners.prefix(2).joined(separator: "・"))と共闘")
                    .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Text("同じ日に記録した仲間がいます。良い装備が出やすくなります。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard(padding: Theme.Spacing.md, highlighted: true)
    }

    // MARK: - 進行中 / 受け取り

    private func progressCard(_ run: ExpeditionRun, now: Date) -> some View {
        let course = run.course
        let progress = Expedition.progress(startedAt: run.startedAt, finishesAt: run.finishesAt, now: now)
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: course?.symbol ?? "figure.walk")
                    .font(.title2)
                    .foregroundStyle(Theme.info)
                    .frame(width: 44, height: 44)
                    .background(Theme.info.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(course?.title ?? "遠征中").font(.headline)
                    Text(Expedition.remainingText(finishesAt: run.finishesAt, now: now))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            ProgressView(value: progress)
                .tint(Theme.info)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard()
    }

    private func claimCard(_ run: ExpeditionRun) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "shippingbox.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.lime)
                    .frame(width: 44, height: 44)
                    .background(Theme.limeSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(run.course?.title ?? "遠征")から帰還").font(.headline)
                    Text("戦利品を持ち帰った").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Button("受け取る") { onClaim(run) }
                .buttonStyle(.gymneePrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard(highlighted: true)
    }

    // MARK: - コース選択

    private var courseList: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(Expedition.courses) { course in
                courseRow(course)
            }
        }
    }

    private func courseRow(_ course: Expedition.Course) -> some View {
        let unlocked = level >= course.minLevel
        let affordable = availableEnergy >= course.energyCost
        return HStack(spacing: Theme.Spacing.md) {
            Group {
                if unlocked {
                    PixelSpriteView(sprite: PixelItemArt.course(id: course.id), palette: .neutral, side: 44)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 44, height: 44)
            .background(
                (unlocked ? Theme.bg2 : Theme.bg2),
                in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(course.title).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Text(unlocked ? course.subtitle : "Lv.\(course.minLevel)で解放")
                    .font(.caption).foregroundStyle(.secondary)
                Text("消費\(course.energyCost) / \(durationText(course))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button("送り出す") { onStart(course) }
                .buttonStyle(.gymneeSecondary)
                .disabled(!unlocked || !affordable)
                .opacity(unlocked && affordable ? 1 : 0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard(padding: Theme.Spacing.md)
    }

    private func durationText(_ course: Expedition.Course) -> String {
        let minutes = course.durationMinutes
        if minutes < 60 { return "\(minutes)分" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours)時間" : "\(hours / 24)日"
    }
}
