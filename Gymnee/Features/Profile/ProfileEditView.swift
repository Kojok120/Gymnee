import SwiftUI
import PhotosUI

/// アバター画像（端末ローカル保存のファイル名）を丸く表示。未設定はシンボル。
/// 画像は PhotoStore に保存し、ファイル名を @AppStorage("gymnee.avatarFilename") に持つ。
struct AvatarView: View {
    let filename: String
    var size: CGFloat = 60

    var body: some View {
        if !filename.isEmpty, let image = PhotoStore.load(filename) {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(Theme.lime)
                .frame(width: size, height: size)
        }
    }
}

/// プロフィール編集（§5）。表示名とアイコン画像を変更する。
struct ProfileEditView: View {
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @AppStorage("gymnee.avatarFilename") private var avatarFilename = ""

    @State private var name = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?

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
                            if !avatarFilename.isEmpty || pickedImage != nil {
                                Button("画像を削除", role: .destructive) {
                                    pickedImage = nil
                                    avatarFilename = ""
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
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .bold()
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if name.isEmpty { name = auth.session?.displayName ?? "" } }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                        pickedImage = ui
                    }
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
            AvatarView(filename: avatarFilename, size: 96)
        }
    }

    private func save() {
        auth.updateDisplayName(name)
        if let pickedImage, let filename = PhotoStore.save(pickedImage) {
            avatarFilename = filename
        }
        if let uid = auth.currentUserId {
            sync.enqueue(PendingChange(entity: "profiles", recordId: uid, operation: .upsert, updatedAt: .now))
        }
        dismiss()
    }
}
