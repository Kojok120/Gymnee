import SwiftUI
import SwiftData
import PhotosUI

/// 進捗写真の追加（§6.7）。既定は private。
struct AddProgressPhotoView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalSyncEngine.self) private var sync

    @State private var image: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var date = Date.now
    @State private var visibility: Visibility = .private
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 260)
                            .frame(maxWidth: .infinity)
                            .listRowInsets(EdgeInsets())
                    }
                    HStack(spacing: Theme.Spacing.md) {
                        if CameraPicker.isAvailable {
                            Button { showCamera = true } label: { Label("撮影", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                                .buttonStyle(.bordered)
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("ライブラリ", systemImage: "photo").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Section("日付") { DatePicker("日付", selection: $date, displayedComponents: .date) }
                Section {
                    Picker("公開範囲", selection: $visibility) {
                        ForEach(Visibility.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("公開範囲")
                } footer: {
                    Text("体型写真は既定で非公開です。")
                }
                Section("メモ") { TextField("メモ", text: $note) }
            }
            .navigationTitle("進捗写真を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }.disabled(image == nil)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image = $0 }.ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    // フルデコードせず背景でダウンサンプル（巨大画像の OOM 回避）。
                    image = await Task.detached(priority: .userInitiated) {
                        PhotoStore.downsample(data: data, maxPixel: 1280)
                    }.value
                }
            }
        }
    }

    private func save() {
        guard let image, let filename = PhotoStore.save(image) else { return }
        let photo = ProgressPhoto(userId: userId, date: date, localPhotoFilename: filename, visibility: visibility, note: note.isEmpty ? nil : note)
        context.insert(photo)
        try? context.save()
        sync.enqueue(PendingChange(entity: "progress_photos", recordId: photo.id, operation: .upsert, updatedAt: photo.updatedAt))
        dismiss()
    }
}
