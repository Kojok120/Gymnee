import SwiftUI

// MARK: - Overline label (大数値の上に置く小ラベル)

/// 大文字・字間広めの小見出し。メトリクスの意味を示す（VOLUME / 1RM / STREAK）。
struct OverlineLabel: View {
    let text: String
    var tint: Color = Theme.textTertiary

    var body: some View {
        Text(text.uppercased())
            .font(.overline)
            .tracking(1.2)
            .foregroundStyle(tint)
    }
}

// MARK: - Section header

/// セクション見出し。左にアクセントの縦バー、右に任意アクション。
struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Capsule()
                .fill(Theme.lime)
                .frame(width: 3, height: 16)
            Text(title)
                .font(.headline)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .tint(Theme.lime)
            }
        }
    }
}

// MARK: - Stat pill / tile (連続日数・PR 件数など)

/// 数値ステータスのタイル。大きな丸数字 + オーバーラインラベル。lime ティント時は発光。
struct StatPill: View {
    let value: String
    let label: String
    var tint: Color = Theme.lime
    var systemImage: String?

    private var isAccent: Bool { tint == Theme.lime || tint == Theme.energy }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.numM)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            OverlineLabel(text: label)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(tint.opacity(isAccent ? 0.30 : 0.0), lineWidth: 1)
        }
        .shadow(color: isAccent ? Theme.limeGlow.opacity(0.5) : .black.opacity(0.08), radius: 12, y: 4)
    }
}

// MARK: - Progress / streak ring

/// 角度グラデの進捗リング。中央に任意コンテンツを差し込める（ストリーク数など）。
struct ProgressRing<Content: View>: View {
    var progress: Double               // 0...1
    var lineWidth: CGFloat = 10
    var size: CGFloat = 92
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.bg3, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(Theme.streakRing, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.limeGlow, radius: 6)
            content()
        }
        .frame(width: size, height: size)
        .animation(.timerTick, value: progress)
    }
}

extension ProgressRing where Content == EmptyView {
    init(progress: Double, lineWidth: CGFloat = 10, size: CGFloat = 92) {
        self.init(progress: progress, lineWidth: lineWidth, size: size) { EmptyView() }
    }
}

// MARK: - Buttons

/// メイン CTA。lime 塗り + 黒文字 + プレス縮小 + ハプティクス。
struct GymneePrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onLime)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, Theme.Spacing.md + 2)
            .padding(.horizontal, Theme.Spacing.lg)
            .background(Theme.limeFill, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .shadow(color: Theme.limeGlow, radius: configuration.isPressed ? 4 : 14, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed)
    }
}

/// サブ CTA。サーフェス塗り + lime 文字。
struct GymneeSecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.lime)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, Theme.Spacing.md + 2)
            .padding(.horizontal, Theme.Spacing.lg)
            .background(Theme.bg2, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.lime.opacity(0.35), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy, value: configuration.isPressed)
    }
}

// MARK: - 通知バッジ（iOS 風の赤い丸 + 数字）

/// 右上に iOS 風の通知バッジを重ねる。`count <= 0` なら何も出さない。99 超は "99+"。
/// アイコンやボタンに `.notificationBadge(unread)` の形で当てる（タップは下のビューへ素通し）。
private struct NotificationBadge: ViewModifier {
    let count: Int

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if count > 0 {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Theme.danger, in: Capsule())
                    .overlay { Capsule().strokeBorder(Theme.bg1, lineWidth: 1.5) }
                    .offset(x: 9, y: -9)
                    .allowsHitTesting(false)
                    .accessibilityLabel("未読 \(count) 件")
            }
        }
    }
}

extension View {
    /// 右上に未読数の赤バッジを重ねる（0 以下は非表示）。
    func notificationBadge(_ count: Int) -> some View {
        modifier(NotificationBadge(count: count))
    }
}

extension ButtonStyle where Self == GymneePrimaryButtonStyle {
    static var gymneePrimary: GymneePrimaryButtonStyle { .init() }
    static func gymneePrimary(fullWidth: Bool) -> GymneePrimaryButtonStyle { .init(fullWidth: fullWidth) }
}
extension ButtonStyle where Self == GymneeSecondaryButtonStyle {
    static var gymneeSecondary: GymneeSecondaryButtonStyle { .init() }
    static func gymneeSecondary(fullWidth: Bool) -> GymneeSecondaryButtonStyle { .init(fullWidth: fullWidth) }
}
