import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// チェックイン時のジム選択（§6.3）。GPS ジオフェンスで現在地のジムを自動補完（候補提示）。
/// リスト表示に加え、地図(MapKit)からピンをタップして選べる「地図」モードを持つ。
struct GymPickerView: View {
    let userId: UUID
    var initialMode: Mode = .list
    var onSelect: (Gym) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LocationService.self) private var location
    @Environment(LocalSyncEngine.self) private var sync
    @Query(sort: \Gym.name) private var gyms: [Gym]
    @State private var search = ""
    @State private var showAdd = false
    @State private var mode: Mode = .list
    /// 削除確認中のジム（誤登録ジムの整理用。§6.3）。
    @State private var deleteTarget: Gym?

    /// 地図(MapKit)から見つけた近隣ジム候補（DB 未登録の初訪問ジムを含む）。
    @State private var nearbyPlaces: [NearbyPlace] = []
    @State private var isSearchingPlaces = false
    @State private var camera: MapCameraPosition = .automatic
    /// 地図でタップ中のピン。即選択せず、まず名前カードを出して確認させる。
    @State private var pendingPin: PendingPin?
    private let placeSearch = PlaceSearchService()

    enum Mode: String, CaseIterable, Identifiable {
        case list, map
        var id: String { rawValue }
        var label: String { self == .list ? "リスト" : "地図" }
        var icon: String { self == .list ? "list.bullet" : "map" }
    }

    /// 地図で選択中のピン（登録済みジム or 地図上の未登録ジム）。
    enum PendingPin: Identifiable, Equatable {
        case registered(Gym)
        case place(NearbyPlace)
        var id: String {
            switch self {
            case .registered(let g): return "g-\(g.id.uuidString)"
            case .place(let p): return "p-\(p.id.uuidString)"
            }
        }
        var name: String {
            switch self {
            case .registered(let g): return g.name
            case .place(let p): return p.name
            }
        }
        var subtitle: String? {
            switch self {
            case .registered(let g): return g.chain
            case .place(let p): return p.address
            }
        }
        var distance: Double? {
            switch self {
            case .registered: return nil
            case .place(let p): return p.distance
            }
        }
        var isRegistered: Bool { if case .registered = self { return true }; return false }
        static func == (lhs: PendingPin, rhs: PendingPin) -> Bool { lhs.id == rhs.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .list: listContent
                case .map: mapContent
                }
            }
            .navigationTitle("ジムを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Picker("表示", selection: $mode) {
                        ForEach(Mode.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            .sheet(isPresented: $showAdd) {
                AddGymView(userId: userId)
            }
            .confirmationDialog(
                "「\(deleteTarget?.name ?? "")」を削除しますか？",
                isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    if let gym = deleteTarget { deleteGym(gym) }
                    deleteTarget = nil
                }
                Button("キャンセル", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("このジムの近くに来た時の自動チェックイン通知も止まります。過去のジム活の記録は残ります。")
            }
            .onAppear {
                mode = initialMode
                location.requestWhenInUse()
                location.refresh()
                setInitialCamera()
                Task { await loadNearbyPlaces() }
            }
            .onChange(of: location.current?.timestamp) { _, _ in
                setInitialCamera()
                Task { await loadNearbyPlaces() }
            }
        }
    }

    // MARK: - List mode

    private var listContent: some View {
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
                    // 自分で登録したジムのみ削除可（プリセットは共有マスタ、他ユーザー作成分は
                    // RLS で削除できず pending が残留するため、createdBy 一致も必須にする）。
                    .swipeActions {
                        if gym.source == .user, gym.createdBy == userId {
                            Button("削除", role: .destructive) { deleteTarget = gym }
                        }
                    }
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
    }

    /// 誤登録ジムの削除。ローカル削除（visits は nullify・設備は cascade）→ 同期キューへ
    /// 削除を積む（サーバも visits.gym_id は set null）→ ジオフェンスを即時更新する
    /// （放置すると削除済みジムの接近通知が届き続けるため。CalendarHome の再監視を待たない）。
    private func deleteGym(_ gym: Gym) {
        let gymId = gym.id
        let equipmentIds = gym.equipment.map(\.id)
        context.delete(gym)
        try? context.save()
        var pending = [PendingChange(entity: "gyms", recordId: gymId, operation: .delete, updatedAt: .now)]
        pending += equipmentIds.map { PendingChange(entity: "gym_equipment", recordId: $0, operation: .delete, updatedAt: .now) }
        sync.enqueueBatch(pending)
        let regions = gyms.filter { $0.id != gymId }.compactMap { g -> (id: UUID, name: String, lat: Double, lng: Double)? in
            guard let lat = g.lat, let lng = g.lng else { return nil }
            return (g.id, g.name, lat, lng)
        }
        location.startMonitoring(gymRegions: regions)
    }

    // MARK: - Map mode

    private var mapContent: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                UserAnnotation()
                // 登録済みジム（座標あり）。
                ForEach(mappableGyms, id: \.id) { gym in
                    Annotation(gym.name, coordinate: CLLocationCoordinate2D(latitude: gym.lat ?? 0, longitude: gym.lng ?? 0)) {
                        pin(tint: Theme.energy, systemImage: "dumbbell.fill", selected: pendingPin == .registered(gym)) {
                            pendingPin = .registered(gym)
                        }
                    }
                }
                // 地図から見つかった未登録ジム。
                ForEach(unregisteredPlaces) { place in
                    Annotation(place.name, coordinate: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)) {
                        pin(tint: .orange, systemImage: "mappin", selected: pendingPin == .place(place)) {
                            pendingPin = .place(place)
                        }
                    }
                }
            }
            // Apple Maps 標準の POI（飲食店など）は隠し、アプリのジムピンだけ表示する。
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .ignoresSafeArea(edges: .bottom)

            // 凡例＋検索中インジケータ。
            HStack(spacing: Theme.Spacing.md) {
                legend(color: Theme.energy, text: "登録済み")
                legend(color: .orange, text: "地図のジム")
                if isSearchingPlaces { ProgressView().controlSize(.mini) }
            }
            .font(.caption2)
            .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, Theme.Spacing.sm)
        }
        // ピンをタップしたら、まず店舗名カードを出して確認させる（即選択しない）。
        .safeAreaInset(edge: .bottom) {
            if let pending = pendingPin {
                selectionCard(pending)
            }
        }
        .animation(.snappy, value: pendingPin)
    }

    /// タップしたピンの店舗名カード。確認してから選択／登録する。
    private func selectionCard(_ pending: PendingPin) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: pending.isRegistered ? "dumbbell.fill" : "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(pending.isRegistered ? Theme.energy : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending.name).font(.headline)
                    HStack(spacing: 6) {
                        Text(pending.isRegistered ? "登録済みのジム" : "地図のジム（未登録）")
                        if let d = pending.distance { Text("· \(formatDistance(d))") }
                        if let sub = pending.subtitle, !sub.isEmpty { Text("· \(sub)").lineLimit(1) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { pendingPin = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button {
                confirm(pending)
            } label: {
                Text(pending.isRegistered ? "このジムを選択" : "このジムを登録して選択")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .prominentLime()
        }
        .gymneeCard()
        .padding(Theme.Spacing.md)
        .background(.clear)
    }

    private func confirm(_ pending: PendingPin) {
        switch pending {
        case .registered(let gym): select(gym)
        case .place(let place): registerAndSelect(place)
        }
    }

    private func pin(tint: Color, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(systemName: systemImage)
                    .font(.caption.bold())
                    // ダークモードで lime 円に白アイコンが埋もれるため濃色（onLime）にする。
                    .foregroundStyle(Theme.onLime)
                    .frame(width: selected ? 40 : 30, height: selected ? 40 : 30)
                    .background(tint, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: selected ? 3 : 2))
                Image(systemName: "triangle.fill")
                    .font(.system(size: selected ? 11 : 8))
                    .foregroundStyle(tint)
                    .rotationEffect(.degrees(180))
                    .offset(y: -3)
            }
            .shadow(radius: selected ? 4 : 2)
        }
        .buttonStyle(.plain)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }

    // MARK: - Selection

    private func select(_ gym: Gym) {
        onSelect(gym)
        dismiss()
    }

    /// 地図から見つけた未登録ジムを登録して選択（同名の既存があれば再利用）。
    private func registerAndSelect(_ place: NearbyPlace) {
        if let existing = gyms.first(where: { $0.name == place.name }) {
            select(existing)
            return
        }
        let gym = Gym(
            name: place.name,
            address: place.address,
            lat: place.lat,
            lng: place.lng,
            source: .user,
            createdBy: userId
        )
        context.insert(gym)
        try? context.save()
        sync.enqueue(PendingChange(entity: "gyms", recordId: gym.id, operation: .upsert, updatedAt: gym.updatedAt))
        select(gym)
    }

    // MARK: - Data

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

    /// 地図に出せる登録ジム（座標あり）。
    private var mappableGyms: [Gym] {
        gyms.filter { $0.lat != nil && $0.lng != nil }
    }

    /// 同名の登録ジムが無い、地図 POI 由来の未登録ジムだけ。
    private var unregisteredPlaces: [NearbyPlace] {
        let names = Set(gyms.map { $0.name })
        return nearbyPlaces.filter { !names.contains($0.name) }
    }

    private func setInitialCamera() {
        if let loc = location.current {
            camera = .region(MKCoordinateRegion(
                center: loc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
        } else if let first = mappableGyms.first, let lat = first.lat, let lng = first.lng {
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
    }

    /// 現在地周辺のジムを地図(MapKit)から検索する。
    private func loadNearbyPlaces() async {
        guard let loc = location.current else { return }
        isSearchingPlaces = true
        defer { isSearchingPlaces = false }
        let found = await placeSearch.nearbyGyms(around: loc.coordinate)
        nearbyPlaces = found.map { place -> NearbyPlace in
            var p = place
            p.distance = loc.distance(from: CLLocation(latitude: place.lat, longitude: place.lng))
            return p
        }
    }
}
