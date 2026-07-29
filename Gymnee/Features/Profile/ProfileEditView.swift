import SwiftUI
import PhotosUI

/// プロフィール編集（§5）。表示名とアイコン（プリセット / 写真）を変更する。
struct ProfileEditView: View {
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @AppStorage("gymnee.avatarFilename") private var avatarFilename = ""
    @AppStorage("gymnee.avatarURL") private var avatarURLString = ""

    @State private var name = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var isSaving = false
    /// 選択中のプリセット（写真を選んだ時点で nil に戻す）。
    @State private var selectedPreset: String?
    @State private var showPhotoPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        avatarPreview
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("アイコン") {
                    AvatarPickerRow(presetURLString: $selectedPreset, onPickPhoto: { showPhotoPicker = true })
                        .listRowBackground(Color.clear)
                    if !avatarFilename.isEmpty || !avatarURLString.isEmpty || pickedImage != nil || selectedPreset != nil {
                        Button("アイコンを消す", role: .destructive) {
                            pickedImage = nil
                            selectedPreset = nil
                            avatarFilename = ""
                            avatarURLString = ""
                        }
                        .font(.caption)
                    }
                }
                Section("表示名") {
                    TextField("表示名", text: $name)
                }
            }
            .navigationTitle("プロフィール編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("保存") { save() }
                            .bold()
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onAppear {
                if name.isEmpty { name = auth.session?.displayName ?? "" }
                if AvatarPreset.isPreset(avatarURLString) { selectedPreset = avatarURLString }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    // フルデコードせず背景でダウンサンプル（巨大画像の OOM 回避）。
                    let image = await Task.detached(priority: .userInitiated) {
                        PhotoStore.downsample(data: data, maxPixel: 1024)
                    }.value
                    pickedImage = image
                    selectedPreset = nil   // 写真を選んだらプリセットの選択は解除する
                }
            }
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let selectedPreset {
            AvatarView(urlString: selectedPreset, size: 96)
        } else if let pickedImage {
            Image(uiImage: pickedImage)
                .resizable().scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
        } else {
            AvatarView(filename: avatarFilename, urlString: avatarURLString, size: 96)
        }
    }

    private func save() {
        isSaving = true
        Task {
            auth.updateDisplayName(name)
            if let selectedPreset {
                // プリセットは擬似 URL を avatar_url に入れるだけ（アップロード不要・サーバー変更不要）。
                avatarURLString = selectedPreset
                avatarFilename = ""
                auth.updateAvatarURL(selectedPreset)
            } else if let pickedImage {
                // ローカルキャッシュ（即時表示用）
                if let filename = PhotoStore.save(pickedImage) { avatarFilename = filename }
                // サーバーへアップロード（他人にも表示されるよう avatar_url を更新）
                if let jpeg = Self.downscaledJPEG(pickedImage),
                   let url = await auth.uploadAvatar(jpeg) {
                    avatarURLString = url
                }
            }
            if let uid = auth.currentUserId {
                sync.enqueue(PendingChange(entity: "profiles", recordId: uid, operation: .upsert, updatedAt: .now))
                await sync.syncNow(force: true)
            }
            isSaving = false
            dismiss()
        }
    }

    /// アップロード用に最大 512px へ縮小して JPEG 化（転送量・保存量を抑える）。
    private static func downscaledJPEG(_ image: UIImage, maxDimension: CGFloat = 512) -> Data? {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
