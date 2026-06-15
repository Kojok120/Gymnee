import SwiftUI
import SwiftData
import PhotosUI

/// チェックインフロー（§6.3）。カメラ→写真→ジム選択(GPS補完)→メモ/合トレ→保存→共有導線。
struct CheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(LocationService.self) private var location
    @Environment(LocalSyncEngine.self) private var sync

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

    var body: some View {
        NavigationStack {
            if let savedVisit {
                CheckInSuccessView(visit: savedVisit) { dismiss() }
            } else {
                form
            }
        }
        .onAppear { location.requestWhenInUse() }
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
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { captured in image = captured }
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
        Section("ジム") {
            Button { showGymPicker = true } label: {
                HStack {
                    Image(systemName: "building.2.fill").foregroundStyle(Theme.energy)
                    Text(selectedGym?.name ?? "ジムを選択")
                        .foregroundStyle(selectedGym == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
        }
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

    // MARK: - Actions

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
            image = ui
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
        try? context.save()
        sync.enqueue(PendingChange(entity: "visits", recordId: visit.id, operation: .upsert, updatedAt: visit.updatedAt))
        savedVisit = visit
    }
}
