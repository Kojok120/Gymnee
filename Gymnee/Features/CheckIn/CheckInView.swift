import SwiftUI
import SwiftData
import PhotosUI
import CoreLocation

/// チェックインフロー（§6.3）。カメラ→写真→ジム選択(GPS自動選択・手動変更可)→メモ/合トレ→保存→共有導線。
struct CheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(LocationService.self) private var location
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(AppErrorCenter.self) private var errors
    @Query(sort: \Gym.name) private var gyms: [Gym]

    @State private var image: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var selectedGym: Gym?
    @State private var showGymPicker = false
    @State private var note = ""
    @State private var partnerNames: [String] = []
    @State private var newPartner = ""
    @State private var visitedAt = Date.now
    @State private var savedVisit: Visit?

    /// GPS で自動選択したかどうか・その距離。ユーザーが手動変更したら自動上書きを止める。
    @State private var isAutoSelected = false
    @State private var autoDistance: CLLocationDistance?
    @State private var userPickedGym = false

    /// 自動選択を許容する最大距離（m）。これを超える最寄りジムは自動選択しない。
    private let autoSelectRadius: CLLocationDistance = 2000

    var body: some View {
        NavigationStack {
            if let savedVisit {
                CheckInSuccessView(visit: savedVisit) { dismiss() }
            } else {
                form
            }
        }
        .onAppear {
            location.requestWhenInUse()
            location.refresh()
            autoSelectNearestGym()
        }
        .onChange(of: location.current?.timestamp) { _, _ in
            autoSelectNearestGym()
        }
    }

    private var form: some View {
        Form {
            photoSection
            gymSection
            Section("メモ") {
                TextField("今日の調子・メニューなど", text: $note, axis: .vertical)
                    .lineLimit(2...4)
            }
            partnerSection
            Section("日時") {
                DatePicker("来店日時", selection: $visitedAt)
            }
        }
        .navigationTitle("チェックイン")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("閉じる") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .bold()
                    .disabled(selectedGym == nil)
            }
        }
        .sheet(isPresented: $showGymPicker) {
            GymPickerView(userId: auth.currentUserId ?? UUID()) { gym in
                selectedGym = gym
                userPickedGym = true
                isAutoSelected = false
                autoDistance = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { captured in
                image = captured
                location.refresh()
                autoSelectNearestGym()
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, newItem in
            Task { await loadPhoto(newItem) }
        }
    }

    // MARK: - Sections

    private var photoSection: some View {
        Section {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .listRowInsets(EdgeInsets())
                    .overlay(alignment: .topTrailing) {
                        Button { self.image = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white, .black.opacity(0.5))
                                .padding(8)
                        }
                    }
            } else {
                HStack(spacing: Theme.Spacing.md) {
                    if CameraPicker.isAvailable {
                        Button { showCamera = true } label: {
                            Label("撮影", systemImage: "camera.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.energy)
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("ライブラリ", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("写真でチェックイン")
        } footer: {
            Text("ジムでの 1 枚が来店記録になります。")
        }
    }

    private var gymSection: some View {
        Section {
            Button { showGymPicker = true } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "building.2.fill").foregroundStyle(Theme.energy)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedGym?.name ?? "ジムを選択")
                            .foregroundStyle(selectedGym == nil ? .secondary : .primary)
                        if let chain = selectedGym?.chain, !chain.isEmpty {
                            Text(chain).font(.caption).foregroundStyle(.secondary)
                        }
                        if isAutoSelected {
                            Label(autoHintText, systemImage: "location.fill")
                                .font(.caption2).foregroundStyle(Theme.energy)
                        }
                    }
                    Spacer()
                    Text("変更").font(.caption).foregroundStyle(Theme.energy)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
        } header: {
            Text("ジム")
        } footer: {
            if selectedGym == nil {
                Text("現在地の近くにジムが見つかると自動で選択されます。手動でも選べます。")
            }
        }
    }

    private var autoHintText: String {
        if let d = autoDistance {
            return "現在地から自動選択（\(formatDistance(d))）"
        }
        return "現在地から自動選択"
    }

    private var partnerSection: some View {
        Section("合トレ相手（任意）") {
            ForEach(partnerNames, id: \.self) { name in
                Label(name, systemImage: "person.fill")
            }
            .onDelete { partnerNames.remove(atOffsets: $0) }
            HStack {
                TextField("名前を追加", text: $newPartner)
                Button("追加") {
                    let trimmed = newPartner.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    partnerNames.append(trimmed)
                    newPartner = ""
                }
                .disabled(newPartner.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Auto select

    /// 現在地から最寄りの登録ジム（座標あり）を自動選択する。
    /// ユーザーが手動選択済み、または既に手動の選択がある場合は上書きしない。
    private func autoSelectNearestGym() {
        guard !userPickedGym, let loc = location.current else { return }
        // 既存の選択が手動由来なら触らない（自動由来なら、より近い候補に更新を許す）。
        if selectedGym != nil && !isAutoSelected { return }

        let nearest = gyms
            .compactMap { gym -> (gym: Gym, dist: CLLocationDistance)? in
                guard let lat = gym.lat, let lng = gym.lng else { return nil }
                let d = loc.distance(from: CLLocation(latitude: lat, longitude: lng))
                return (gym, d)
            }
            .min { $0.dist < $1.dist }

        guard let nearest, nearest.dist <= autoSelectRadius else { return }
        selectedGym = nearest.gym
        autoDistance = nearest.dist
        isAutoSelected = true
    }

    // MARK: - Actions

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
            image = ui
            autoSelectNearestGym()
        }
    }

    private func save() {
        guard let userId = auth.currentUserId, let gym = selectedGym else { return }
        let filename = image.flatMap { PhotoStore.save($0) }
        let loc = location.current
        let visit = Visit(
            userId: userId,
            visitedAt: visitedAt,
            gym: gym,
            localPhotoFilename: filename,
            lat: loc?.coordinate.latitude,
            lng: loc?.coordinate.longitude,
            note: note.isEmpty ? nil : note
        )
        context.insert(visit)
        for name in partnerNames {
            let partner = VisitPartner(partnerUserId: UUID(), partnerDisplayName: name, visit: visit)
            context.insert(partner)
        }
        do {
            try context.save()
        } catch {
            errors.report("チェックインを保存できませんでした。\(error.localizedDescription)")
            return
        }
        sync.enqueue(PendingChange(entity: "visits", recordId: visit.id, operation: .upsert, updatedAt: visit.updatedAt))
        savedVisit = visit
    }
}
