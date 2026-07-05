import SwiftUI
import UIKit

/// 共有カードを画像に焼き込む（§6.6）。SwiftUI ImageRenderer を使用。
@MainActor
enum ShareCardRenderer {
    /// カードを高解像度の UIImage にレンダリングする。
    static func render(content: ShareCardContent, theme: ShareCardTheme, side: CGFloat = 360, scale: CGFloat = 3) -> UIImage? {
        let view = ShareCardView(content: content, theme: theme, side: side)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.uiImage
    }

    /// Instagram ストーリーズ用の 9:16（1080×1920 @scale3）。ブランド背景の中央にカードを置いて焼き込む。
    /// ストーリーズは背景画像が全画面に敷かれるため、カード単体（正方形）ではなくこの形で渡す。
    static func renderStory(content: ShareCardContent, theme: ShareCardTheme, scale: CGFloat = 3) -> UIImage? {
        let view = ZStack {
            LinearGradient(
                colors: [Color(hexF: 0x0B0D0C), Color(hexF: 0x141A12), Color(hexF: 0x0B0D0C)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Theme.lime.opacity(0.18), .clear],
                center: .init(x: 0.5, y: 0.32), startRadius: 0, endRadius: 320
            )
            VStack(spacing: 22) {
                ShareCardView(content: content, theme: theme, side: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 14)
                Label("Gymnee", systemImage: "figure.strengthtraining.traditional")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.lime)
            }
        }
        .frame(width: 360, height: 640)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.uiImage
    }
}
