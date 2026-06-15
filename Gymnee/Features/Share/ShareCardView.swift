import SwiftUI

/// 共有カードの見た目（§6.6）。写真の上にサマリをオーバーレイ。ImageRenderer で画像化される。
struct ShareCardView: View {
    let content: ShareCardContent
    let theme: ShareCardTheme
    /// 基準サイズ（正方形）。レンダリング時は scale で高解像度化する。
    var side: CGFloat = 360

    var body: some View {
        ZStack {
            background
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(theme == .light ? 0 : 0.7)],
                startPoint: .center,
                endPoint: .bottom
            )
            content_overlay
        }
        .frame(width: side, height: side)
        .clipped()
    }

    @ViewBuilder
    private var background: some View {
        if let image = content.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .overlay(theme.textColor == .black ? Color.white.opacity(theme.overlayOpacity) : Color.black.opacity(theme.overlayOpacity))
        } else {
            LinearGradient(colors: [Theme.deep, theme.accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var content_overlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Gymnee", systemImage: "figure.strengthtraining.traditional")
                    .font(.system(size: side * 0.05, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.accent)
                Spacer()
                Text(content.date, format: .dateTime.year().month().day())
                    .font(.system(size: side * 0.035, weight: .semibold))
                    .foregroundStyle(theme.textColor.opacity(0.9))
            }
            Spacer()
            VStack(alignment: .leading, spacing: side * 0.025) {
                if content.showGym, let gym = content.gymName {
                    Label(gym, systemImage: "location.fill")
                        .font(.system(size: side * 0.05, weight: .bold))
                        .foregroundStyle(theme.textColor)
                }
                if content.showExercises, let ex = content.exerciseSummary {
                    Text(ex)
                        .font(.system(size: side * 0.04, weight: .medium))
                        .foregroundStyle(theme.textColor.opacity(0.95))
                        .lineLimit(2)
                }
                HStack(spacing: side * 0.03) {
                    if content.showStreak, let streak = content.streak, streak > 0 {
                        chip(icon: "flame.fill", text: "\(streak)日連続")
                    }
                    if content.showPR, let pr = content.prText {
                        chip(icon: "trophy.fill", text: pr)
                    }
                }
            }
        }
        .padding(side * 0.06)
    }

    private func chip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: side * 0.038, weight: .bold))
            .padding(.horizontal, side * 0.035)
            .padding(.vertical, side * 0.02)
            .background(theme.accent, in: Capsule())
            .foregroundStyle(.black)
    }
}
