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
}
