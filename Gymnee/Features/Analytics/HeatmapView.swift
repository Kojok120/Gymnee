import SwiftUI

/// 来店頻度ヒートマップ（§6.2 / §6.8）。貢献グラフ風の年間ビュー。
struct HeatmapView: View {
    /// 日(startOfDay) → 来店回数。
    let counts: [Date: Int]
    var weeks: Int = 26
    var tint: Color = Theme.energy
    /// 横スクロールせず、曜日7列のグリッドでカード幅いっぱいに日次表示する（フレンド詳細の直近数週向け）。
    var fillWidth: Bool = false
    /// 貢献グラフ（曜日7行 × 週列）を横スクロールなしでカード幅いっぱいに敷き詰める（分析の固定期間向け）。
    var contribution: Bool = false

    private let calendar = Calendar.current
    private let cell: CGFloat = 13
    private let spacing: CGFloat = 3

    var body: some View {
        if contribution { contributionGraph }
        else if fillWidth { fillWidthGrid }
        else { scrollingWeeks }
    }

    // MARK: - 全幅・貢献グラフ（曜日7行 × 週列。固定期間を横スクロールなしで敷き詰める）

    private var contributionGraph: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(weeks, 1))
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(contributionDays, id: \.self) { day in
                    let count = counts[calendar.startOfDay(for: day)] ?? 0
                    let isFuture = day > Date.now
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(for: count).opacity(isFuture ? 0.15 : 1))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            legend
        }
    }

    /// 曜日行×週列で並べる日付列。LazyVGrid は左→右・上→下に流すため、「各曜日について全週」を
    /// 順に並べると 7 行（曜日）× weeks 列（週・古→新）の貢献グラフになる。
    private var contributionDays: [Date] {
        (0..<7).flatMap { dow in
            weekStarts.compactMap { calendar.date(byAdding: .day, value: dow, to: $0) }
        }
    }

    /// 濃淡の凡例（少→多）。
    private var legend: some View {
        HStack(spacing: 4) {
            Text("少").font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2).fill(color(for: level)).frame(width: 11, height: 11)
            }
            Text("多").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - 全幅（曜日7列 × 週行）の日次グリッド

    private var fillWidthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 7)
        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(gridDays, id: \.self) { day in
                let count = counts[calendar.startOfDay(for: day)] ?? 0
                let isFuture = day > Date.now
                RoundedRectangle(cornerRadius: 3)
                    .fill(color(for: count).opacity(isFuture ? 0.15 : 1))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }

    /// 直近 `weeks` 週分の全日（週頭→曜日順）。グリッドは週行・曜日列で並ぶ。
    private var gridDays: [Date] {
        weekStarts.flatMap { ws in
            (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: ws) }
        }
    }

    // MARK: - 横スクロール（貢献グラフ風・年間ビュー）

    private var scrollingWeeks: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(weekStarts, id: \.self) { weekStart in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { dow in
                                if let day = calendar.date(byAdding: .day, value: dow, to: weekStart) {
                                    cellView(for: day)
                                }
                            }
                        }
                        .id(weekStart)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                if let last = weekStarts.last { proxy.scrollTo(last, anchor: .trailing) }
            }
        }
    }

    private func cellView(for day: Date) -> some View {
        let count = counts[calendar.startOfDay(for: day)] ?? 0
        let isFuture = day > Date.now
        return RoundedRectangle(cornerRadius: 2)
            .fill(color(for: count).opacity(isFuture ? 0.15 : 1))
            .frame(width: cell, height: cell)
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0: return Color.secondary.opacity(0.15)
        case 1: return tint.opacity(0.45)
        case 2: return tint.opacity(0.7)
        default: return tint
        }
    }

    /// 直近 `weeks` 週分の各週の開始日（週頭）。
    private var weekStarts: [Date] {
        let today = calendar.startOfDay(for: .now)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<weeks).reversed().compactMap {
            calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek)
        }
    }
}
