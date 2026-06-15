import SwiftUI

/// ソーシャルフィード（§6.11）。P6 でフォロー・フィード・合トレタグを実装する。
struct SocialFeedView: View {
    var body: some View {
        NavigationStack {
            ComingSoonView(title: "ソーシャル", systemImage: "person.2.fill", note: "P6 でフォロー・フィード・合トレタグを実装します。")
                .navigationTitle("ソーシャル")
        }
    }
}
