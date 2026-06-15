import SwiftUI

/// 来店頻度ヒートマップ（§6.2 / §6.8）。貢献グラフ風の年間ビュー。
struct HeatmapView: View {
    /// 日(startOfDay) → 来店回数。
    let counts: [Date: Int]
    var weeks: Int = 26
    var tint: Color = Theme.energy

    private let calendar = Calendar.current
    private let cell: CGFloat = 13
    private let spacing: CGFloat = 3

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(weekStarts, id: \.self) { weekStart in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { dow in
                                let day = calendar.date(byAdding: .day, value: dow, to: weekStart)!
                                cellView(for: day)
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
