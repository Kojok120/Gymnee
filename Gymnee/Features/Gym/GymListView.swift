import SwiftUI
import SwiftData

/// ジム管理（§6.4）。プリセット＋自己登録、ジム別サマリー。
struct GymListView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Query(sort: \Gym.name) private var gyms: [Gym]
    @Query private var visits: [Visit]

    @State private var search = ""
    @State private var showAdd = false

    init(userId: UUID) {
        self.userId = userId
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId })
    }

    var body: some View {
        gymList
        .navigationTitle("ジム")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddGymView(userId: userId)
        }
    }

    private var gymList: some View {
        List {
            if !favorites.isEmpty {
                Section("お気に入り") {
                    ForEach(favorites) { gymRow($0) }
                }
            }
            Section("すべてのジム") {
                ForEach(filtered) { gymRow($0) }
            }
        }
        .searchable(text: $search, prompt: "ジムを検索")
        .overlay {
            if gyms.isEmpty {
                EmptyStateView(systemImage: "building.2", title: "ジムがありません", message: "右上の＋から追加できます。")
            }
        }
    }

    private func gymRow(_ gym: Gym) -> some View {
        NavigationLink(value: AppRoute.gymDetail(gym)) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gym.name).font(.body)
                    if let chain = gym.chain, gym.source == .preset {
                        Text(chain).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                let count = visitCounts[gym.id] ?? 0
                if count > 0 {
                    Text("\(count)回").font(.caption.bold()).foregroundStyle(Theme.energy)
                }
                Button {
                    gym.isFavorite.toggle()
                    gym.updatedAt = .now
                    try? context.save()
                    sync.enqueue(PendingChange(entity: "gyms", recordId: gym.id, operation: .upsert, updatedAt: gym.updatedAt))
                } label: {
                    Image(systemName: gym.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(gym.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var favorites: [Gym] {
        gyms.filter { $0.isFavorite }
    }

    private var filtered: [Gym] {
        guard !search.isEmpty else { return gyms }
        return gyms.filter { $0.name.localizedCaseInsensitiveContains(search) || ($0.chain?.localizedCaseInsensitiveContains(search) ?? false) }
    }

    private var visitCounts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for visit in visits {
            guard let gymId = visit.gym?.id else { continue }
            counts[gymId, default: 0] += 1
        }
        return counts
    }
}
