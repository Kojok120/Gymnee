import SwiftUI

/// ローカルにあれば即表示、無ければ storage 参照(photoURL="bucket/path")からDLしてローカルに復元表示する。
/// 機種変更/再インストール後でも写真が消えないようにするための表示コンポーネント（監査T2a）。
struct SyncedPhoto<Placeholder: View>: View {
    let filename: String?
    /// "bucket/path" 形式のストレージ参照（photoURL）。http(s) の公開URLはここでは扱わない。
    let ref: String?
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(AuthService.self) private var auth
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                placeholder()
            }
        }
        .task(id: "\(filename ?? "")|\(ref ?? "")") { await load() }
    }

    private func load() async {
        if let filename, let img = PhotoStore.load(filename) { image = img; return }
        // ローカルに無い → リモート参照から復元（"bucket/path"のみ。公開httpはAsyncImage管轄）。
        guard let ref, !ref.hasPrefix("http") else { return }
        guard let data = await auth.downloadPhoto(ref: ref) else { return }
        let saved: UIImage?
        if let filename {
            saved = PhotoStore.writeData(data, as: filename) // モデルのファイル名で復元（次回はローカルヒット）
        } else {
            saved = UIImage(data: data)
        }
        image = saved
    }
}
