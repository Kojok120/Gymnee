import SwiftUI
import UIKit

/// 「その他SNS」で共有する画像のプレビューと書き出し。
///
/// 見た目はアプリ内フィードと同じ `PostCardView`（`.share` は種目ごとの全セットを展開した高密度版）。
/// テーマ選択は持たない ―― プレビューと実際に共有される画像を一致させることを最優先にしているため。
struct SharePreviewSheet: View {
    let entry: FeedEntry
    /// 投稿写真（コンポーザが読み込み済みのものを渡す。ImageRenderer 上では非同期ロードが走らないため）。
    var photo: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var rendered: UIImage?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    if let rendered {
                        Image(uiImage: rendered)
                            .resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                            .shadow(radius: 8)
                    } else {
                        ProgressView().frame(height: 320)
                    }
                    actions
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("画像で共有")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
            }
            .task { rendered = PostCardRenderer.render(entry: entry, photo: photo) }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if let rendered {
            VStack(spacing: Theme.Spacing.md) {
                ShareLink(item: Image(uiImage: rendered),
                          preview: SharePreview("Gymnee", image: Image(uiImage: rendered))) {
                    Label("共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent).prominentLime()

                // ストーリーズ直接共有（Meta App ID 設定済み＋Instagram インストール時のみ表示）。
                if InstagramSharing.isAvailable {
                    Button {
                        if let story = PostCardRenderer.renderStory(entry: entry, photo: photo) {
                            InstagramSharing.shareToStories(background: story)
                        } else {
                            message = "画像の生成に失敗しました"
                        }
                    } label: {
                        Label("Instagramストーリーズ", systemImage: "camera.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    UIImageWriteToSavedPhotosAlbum(rendered, nil, nil, nil)
                    message = "写真に保存しました"
                } label: {
                    Label("写真に保存", systemImage: "photo.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
