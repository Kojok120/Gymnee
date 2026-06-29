import SwiftUI
import SwiftData
import PhotosUI

/// 進捗写真の追加（§6.7）。既定は private。
struct AddProgressPhotoView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(AuthService.self) private var auth
    @Environment(AppErrorCenter.self) private var errors

    @State private var image: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var date = Date.now
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
                    Label("非公開（自分のみ）", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("体型写真は常に非公開です。他のユーザーには表示されません。")
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
        guard let image, let filename = PhotoStore.save(image) else {
            errors.report("写真を保存できませんでした。")
            return
        }
        // 体型写真はセンシティブなため常に非公開（公開させない）。
        let photo = ProgressPhoto(userId: userId, date: date, localPhotoFilename: filename, visibility: .private, note: note.isEmpty ? nil : note)
        context.insert(photo)
        do {
            try context.save()
        } catch {
            errors.report("写真を保存できませんでした。\(error.localizedDescription)")
            return
        }
        sync.enqueue(PendingChange(entity: "progress_photos", recordId: photo.id, operation: .upsert, updatedAt: photo.updatedAt))
        // リモートにもアップロードして再インストール後の消失を防ぐ（best-effort）。
        let pid = photo.id
        Task {
            guard let jpeg = image.jpegData(compressionQuality: 0.8),
                  let ref = await auth.uploadPhoto(bucket: "progress-photos", filename: filename, jpeg: jpeg) else { return }
            // 画面破棄/削除後に元オブジェクトを触らない（id で再取得し、存在する時だけ書く）。
            guard let fresh = (try? context.fetch(FetchDescriptor<ProgressPhoto>(predicate: #Predicate { $0.id == pid })))?.first else { return }
            fresh.photoURL = ref; fresh.updatedAt = .now; fresh.isDirty = true
            try? context.save()
            sync.enqueue(PendingChange(entity: "progress_photos", recordId: pid, operation: .upsert, updatedAt: fresh.updatedAt))
        }
        dismiss()
    }
}
