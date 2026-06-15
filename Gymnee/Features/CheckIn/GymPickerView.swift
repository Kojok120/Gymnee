import SwiftUI
import SwiftData

/// チェックイン時のジム選択（§6.3）。GPS ジオフェンスで現在地のジムを自動補完（候補提示）。
struct GymPickerView: View {
    let userId: UUID
    var onSelect: (Gym) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @Query(sort: \Gym.name) private var gyms: [Gym]
    @State private var search = ""
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if !nearby.isEmpty {
                    Section {
                        ForEach(nearby, id: \.gym.id) { item in
                            Button { select(item.gym) } label: {
                                HStack {
                                    Image(systemName: "location.fill").foregroundStyle(Theme.energy)
                                    Text(item.gym.name)
                                    Spacer()
                                    Text(formatDistance(item.distance))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .tint(.primary)
                        }
                    } header: {
                        Label("近くのジム", systemImage: "location")
                    }
                }

                Section("すべてのジム") {
                    ForEach(filtered) { gym in
                        Button { select(gym) } label: {
                            HStack {
                                Text(gym.name)
                                if let chain = gym.chain, gym.source == .preset {
                                    Text(chain).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .tint(.primary)
                    }
                }

                Section {
                    Button {
                        showAdd = true
                    } label: {
                        Label("新しいジムを追加", systemImage: "plus.circle.fill")
                    }
                }
            }
            .searchable(text: $search, prompt: "ジムを検索")
            .navigationTitle("ジムを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddGymView(userId: userId)
            }
            .onAppear { location.requestWhenInUse() }
        }
    }

    private func select(_ gym: Gym) {
        onSelect(gym)
        dismiss()
    }

    private struct NearbyGym { let gym: Gym; let distance: Double }

    /// 現在地から近い順（座標を持つジムのみ、近距離上位）。
    private var nearby: [NearbyGym] {
        guard location.current != nil else { return [] }
        return gyms
            .compactMap { gym -> NearbyGym? in
                guard let d = location.distance(toLat: gym.lat, lng: gym.lng) else { return nil }
                return NearbyGym(gym: gym, distance: d)
            }
            .sorted { $0.distance < $1.distance }
            .prefix(5)
            .map { $0 }
    }

    private var filtered: [Gym] {
        guard !search.isEmpty else { return gyms }
        return gyms.filter { $0.name.localizedCaseInsensitiveContains(search) || ($0.chain?.localizedCaseInsensitiveContains(search) ?? false) }
    }
}
