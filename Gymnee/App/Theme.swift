import SwiftUI
import UIKit

/// アプリ共通のデザイントークン。色・余白・角丸を一元管理し、各画面で再利用する。
enum Theme {
    // MARK: - Colors
    /// ブランドのアクセント（エネルギッシュなライム）。Assets の AccentColor と対応。
    static let accent = Color("AccentColor")
    static let energy = Color(red: 0.45, green: 0.85, blue: 0.25)
    static let deep = Color(red: 0.10, green: 0.12, blue: 0.16)

    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)

    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Radius
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
        static let pill: CGFloat = 999
    }
}

/// カード状コンテナの共通修飾。
struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.lg
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

extension View {
    func gymneeCard(padding: CGFloat = Theme.Spacing.lg) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

/// 空状態の共通表示。
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        }
    }
}
