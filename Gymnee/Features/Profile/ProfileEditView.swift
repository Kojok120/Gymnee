import SwiftUI
import PhotosUI

/// アバター画像を丸く表示。端末ローカルのキャッシュ（自分用＝即時）→ サーバー公開URL → シンボル の順。
/// 自分の画像は PhotoStore に保存しファイル名を @AppStorage("gymnee.avatarFilename")、
/// 公開URLを @AppStorage("gymnee.avatarURL") に持つ。他人は urlString のみ。
struct AvatarView: View {
    var filename: String = ""
    var urlString: String? = nil
    var size: CGFloat = 60

    var body: some View {
        Group {
            if !filename.isEmpty, let image = PhotoStore.load(filename) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        symbol
                    }
                }
            } else {
                symbol
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var symbol: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable().scaledToFit()
            .foregroundStyle(Theme.lime)
    }
}

/// プロフィール編集（§5）。表示名とアイコン画像を変更する。
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: Theme.Spacing.md) {
                            avatarPreview
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label("アイコン画像を変更", systemImage: "photo")
                            }
                            if !avatarFilename.isEmpty || !avatarURLString.isEmpty || pickedImage != nil {
                                Button("画像を削除", role: .destructive) {
                                    pickedImage = nil
                                    avatarFilename = ""
                                    avatarURLString = ""
                                }
                                .font(.caption)
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
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
            .onAppear { if name.isEmpty { name = auth.session?.displayName ?? "" } }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    // フルデコードせず背景でダウンサンプル（巨大画像の OOM 回避）。
                    let image = await Task.detached(priority: .userInitiated) {
                        PhotoStore.downsample(data: data, maxPixel: 1024)
                    }.value
                    pickedImage = image
                }
            }
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let pickedImage {
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
            if let pickedImage {
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
