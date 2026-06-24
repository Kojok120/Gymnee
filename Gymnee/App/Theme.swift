import SwiftUI
import UIKit

// MARK: - Adaptive color helper

extension Color {
    /// ライト/ダークで切り替わる動的カラー。両モードを意図的にデザインするための基盤。
    init(light: UInt, dark: UInt) {
        self = Color(uiColor: UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    fileprivate convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// アプリ共通のデザイントークン。色・タイポ・余白・角丸・モーションを一元管理する。
/// 設計言語: ダークファースト + 単一の予約アクセント「Gymnee Lime」。
/// Lime は達成/アクティブ状態（完了セット・ストリーク・PR）にのみ使い、特別感を保つ。
enum Theme {
    // MARK: - Brand accent (Gymnee Lime)

    /// サーフェス上のアクセント（テキスト/アイコン/ストローク）。可読性のためライトは深め。
    static let lime = Color(light: 0x5FA000, dark: 0xC6FF3D)
    /// 塗り（ボタン/チップ背景）。両モードで鮮烈。上には `onLime`（ほぼ黒）を載せる。
    static let limeFill = Color(light: 0xB6F23A, dark: 0xC6FF3D)
    /// 塗りの上のテキスト/アイコン色。
    static let onLime = Color(red: 0.043, green: 0.051, blue: 0.047)
    /// ハイライト/プレス時のエッジ。
    static let limeBright = Color(light: 0x8FD400, dark: 0xD8FF6B)
    /// アクティブカード下の発光（グロー）。
    static let limeGlow = Color(red: 0.78, green: 1.0, blue: 0.24).opacity(0.28)
    /// 低彩度のティント背景。
    static let limeSoft = Color(light: 0x5FA000, dark: 0xC6FF3D).opacity(0.14)

    // MARK: - Neutral surfaces (warm charcoal / warm off-white)

    /// アプリ背景。
    static let bg0 = Color(light: 0xF6F8F2, dark: 0x0B0D0C)
    /// 基本サーフェス / カード。
    static let bg1 = Color(light: 0xFFFFFF, dark: 0x131614)
    /// 一段持ち上がったサーフェス / 入力欄 / シート。
    static let bg2 = Color(light: 0xF0F3EA, dark: 0x1C201D)
    /// ヘアライン / 区切り / プレス状態。
    static let bg3 = Color(light: 0xE2E7DA, dark: 0x272C28)

    // MARK: - Text roles (システムの .primary/.secondary も併用可)

    static let textPrimary = Color(light: 0x16190F, dark: 0xF4F7F2)
    static let textSecondary = Color(light: 0x5A6152, dark: 0xA7AEA6)
    static let textTertiary = Color(light: 0x8C9384, dark: 0x6E756C)

    // MARK: - Semantic accents (Lime 以外は控えめに)

    static let success = lime
    static let warning = Color(light: 0xE08A00, dark: 0xFFB23E)   // レスト/期限
    static let danger = Color(light: 0xE0463F, dark: 0xFF5C5C)    // 削除/連続途切れ
    static let info = Color(light: 0x0AA3D9, dark: 0x4ECBFF)      // 有酸素/心拍
    static let series2 = Color(light: 0x7C4DFF, dark: 0xB388FF)   // ボリューム第2系列

    // MARK: - Legacy aliases (既存 90 ファイルとの後方互換。撤去しない)

    static let accent = lime
    static let energy = lime
    static let deep = Color(light: 0x16190F, dark: 0x0B0D0C)
    static let cardBackground = bg1
    static let groupedBackground = bg0

    // MARK: - Gradients

    /// PR / 祝祭用。
    static let celebration = LinearGradient(
        colors: [Color(hexF: 0xD8FF6B), Color(hexF: 0x8FD400)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// ストリークリング塗り（角度グラデ）。
    static let streakRing = AngularGradient(
        colors: [Color(hexF: 0x8FD400), Color(hexF: 0xC6FF3D), Color(hexF: 0xD8FF6B), Color(hexF: 0x8FD400)],
        center: .center
    )
    /// オンボーディング等のヒーロー背景。
    static let heroBackground = LinearGradient(
        colors: [Color(hexF: 0x0B0D0C), Color(hexF: 0x141A12), Color(hexF: 0x1E2A12)],
        startPoint: .top, endPoint: .bottom
    )

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
        static let card: CGFloat = 20
        static let sheet: CGFloat = 28
        static let button: CGFloat = 16
        static let chip: CGFloat = 12
        static let pill: CGFloat = 999
    }

    // MARK: - Muscle group palette (分析の部位色分け)

    static func muscleColor(_ group: MuscleGroup) -> Color {
        switch group {
        case .chest: return Color(hexF: 0xFF6B6B)
        case .back: return Color(hexF: 0x4ECBFF)
        case .legs: return Color(hexF: 0xC6FF3D)
        case .shoulders: return Color(hexF: 0xFFB23E)
        case .biceps: return Color(hexF: 0xB388FF)
        case .triceps: return Color(hexF: 0xFF9FE5)
        case .core: return Color(hexF: 0x5BE7C4)
        case .glutes: return Color(hexF: 0xFF8A5B)
        case .fullBody: return Color(hexF: 0x9AA0FF)
        }
    }
}

// MARK: - Convenience hex Color (静的トークン用、単色)

extension Color {
    init(hexF: UInt) {
        self.init(
            red: Double((hexF >> 16) & 0xFF) / 255,
            green: Double((hexF >> 8) & 0xFF) / 255,
            blue: Double(hexF & 0xFF) / 255
        )
    }
}

// MARK: - Typography (数値は SF Pro Rounded + monospacedDigit)

extension Font {
    /// ヒーロー数値（タイマー・主要メトリクス）。
    static let numXL = Font.system(size: 48, weight: .bold, design: .rounded).monospacedDigit()
    static let numL = Font.system(size: 32, weight: .bold, design: .rounded).monospacedDigit()
    static let numM = Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
    static let numS = Font.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit()
    /// 大数値の上に置く小ラベル（大文字・字間広め）。
    static let overline = Font.system(size: 11, weight: .semibold, design: .rounded)
}

// MARK: - Motion (物理ベースの spring プリセット)

extension Animation {
    /// タップ/トグル/セット完了。
    static let snappy = Animation.spring(response: 0.30, dampingFraction: 0.82)
    /// PR ポップ/メダル登場（オーバーシュート＝喜び）。
    static let bouncy = Animation.spring(response: 0.45, dampingFraction: 0.62)
    /// シート/ナビゲーション/レイアウト。
    static let smooth = Animation.spring(response: 0.55, dampingFraction: 0.92)
    /// リング/数値の更新（跳ねない）。
    static let timerTick = Animation.spring(response: 0.20, dampingFraction: 1.0)
}

// MARK: - Elevation / Card

/// カード状コンテナ。不透明サーフェス + ソフトシャドウ。達成カードは lime グローを下に重ねる。
struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.lg
    var radius: CGFloat = Theme.Radius.card
    var highlighted: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.bg1, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.lime.opacity(0.5), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
            .shadow(color: highlighted ? Theme.limeGlow : .clear, radius: 22, x: 0, y: 0)
    }
}

extension View {
    func gymneeCard(padding: CGFloat = Theme.Spacing.lg, highlighted: Bool = false) -> some View {
        modifier(CardModifier(padding: padding, highlighted: highlighted))
    }
}

// MARK: - Empty state

/// 空状態の共通表示。
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String?
    /// 空状態から次の一歩を促すCTA（任意）。
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.lime)
            }
        }
    }
}
