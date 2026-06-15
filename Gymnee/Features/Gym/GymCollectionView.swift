import SwiftUI

/// ジム図鑑（§6.4）。訪問済みジムをコレクションとして可視化（出張・合トレと好相性）。
struct GymCollectionView: View {
    let gyms: [Gym]
    let visitCounts: [UUID: Int]

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.md)]

    private var visited: [Gym] { gyms.filter { (visitCounts[$0.id] ?? 0) > 0 } }
    private var unvisited: [Gym] { gyms.filter { (visitCounts[$0.id] ?? 0) == 0 } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                summary

                SectionHeader(title: "訪問済み (\(visited.count))")
                LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                    ForEach(visited) { card($0, collected: true) }
                }

                if !unvisited.isEmpty {
                    SectionHeader(title: "未訪問 (\(unvisited.count))")
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                        ForEach(unvisited) { card($0, collected: false) }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.groupedBackground)
        .overlay {
            if gyms.isEmpty {
                EmptyStateView(systemImage: "books.vertical", title: "図鑑は空です", message: "チェックインするとジムが集まります。")
            }
        }
    }

    private var summary: some View {
        HStack(spacing: Theme.Spacing.md) {
            StatPill(value: "\(visited.count)", label: "コンプ済み")
            StatPill(value: "\(gyms.count)", label: "登録ジム")
            StatPill(value: "\(visitCounts.values.reduce(0, +))", label: "総来店")
        }
    }

    private func card(_ gym: Gym, collected: Bool) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: collected ? "building.2.fill" : "building.2")
                .font(.system(size: 32))
                .foregroundStyle(collected ? Theme.energy : Color.secondary.opacity(0.4))
            Text(gym.name)
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(collected ? .primary : .secondary)
            if collected {
                Text("\(visitCounts[gym.id] ?? 0)回")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .gymneeCard()
        .opacity(collected ? 1 : 0.7)
    }
}
