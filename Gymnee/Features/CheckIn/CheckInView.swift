import SwiftUI

/// チェックインフロー（§6.3）。P1 でカメラ→ジム選択(GPS補完)→メモ→保存→共有導線を実装する。
struct CheckInView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ComingSoonView(title: "チェックイン", systemImage: "camera.fill", note: "P1 でカメラ撮影→ジム選択(GPS補完)→来店保存を実装します。")
                .navigationTitle("チェックイン")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("閉じる") { dismiss() }
                    }
                }
        }
    }
}
