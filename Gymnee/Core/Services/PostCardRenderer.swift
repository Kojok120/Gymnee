import SwiftUI
import UIKit

/// 投稿カードを画像へ焼き込む（§6.6）。SwiftUI ImageRenderer を使用。
/// 描画は `PostCardView(style: .share)` に一本化しており、アプリ内フィードと同じ意匠のまま
/// 種目ごとの全セットを展開した高密度版が出る。
@MainActor
enum PostCardRenderer {
    /// フィード投稿相当の 1 枚（幅 side・高さは内容なり）。
    static func render(entry: FeedEntry, photo: UIImage?, side: CGFloat = 360, scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(content: card(entry: entry, photo: photo, side: side))
        renderer.scale = scale
        return renderer.uiImage
    }

    /// Instagram ストーリーズ用の 9:16（1080×1920 @scale3）。
    /// ストーリーズは背景画像が全画面に敷かれるため、カード単体ではなくブランド背景に載せた形で渡す。
    static func renderStory(entry: FeedEntry, photo: UIImage?, scale: CGFloat = 3) -> UIImage? {
        let view = ZStack {
            LinearGradient(
                colors: [Color(hexF: 0x0B0D0C), Color(hexF: 0x141A12), Color(hexF: 0x0B0D0C)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Theme.lime.opacity(0.18), .clear],
                center: .init(x: 0.5, y: 0.32), startRadius: 0, endRadius: 320
            )
            card(entry: entry, photo: photo, side: 300)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 24, y: 14)
        }
        .frame(width: 360, height: 640)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.uiImage
    }

    private static func card(entry: FeedEntry, photo: UIImage?, side: CGFloat) -> some View {
        PostCardView(entry: entry, style: .share, side: side, preloadedPhoto: photo)
            .environment(\.colorScheme, .dark)
    }
}
