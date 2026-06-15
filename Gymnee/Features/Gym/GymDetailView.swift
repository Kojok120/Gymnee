import SwiftUI
import SwiftData

/// ジム別サマリー（§6.4）。単一タイムライン上の、このジムへの来店回数・最終来店・履歴。
struct GymDetailView: View {
    let gym: Gym
    let userId: UUID

    @Query private var visits: [Visit]

    init(gym: Gym, userId: UUID) {
        self.gym = gym
        self.userId = userId
        let gymId = gym.id
        _visits = Query(
            filter: #Predicate<Visit> { $0.userId == userId && $0.gym?.id == gymId },
            sort: \Visit.visitedAt,
            order: .reverse
        )
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: Theme.Spacing.md) {
                    StatPill(value: "\(visits.count)", label: "来店")
                    StatPill(value: lastVisitText, label: "最終来店")
                    StatPill(value: gym.source == .preset ? "公式" : "自己登録", label: "種別")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("来店履歴") {
                if visits.isEmpty {
                    Text("まだ来店記録がありません。").foregroundStyle(.secondary)
                } else {
                    ForEach(visits) { visit in
                        VisitRow(visit: visit)
                    }
                }
            }
        }
        .navigationTitle(gym.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lastVisitText: String {
        guard let last = visits.first?.visitedAt else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: last)
    }
}
