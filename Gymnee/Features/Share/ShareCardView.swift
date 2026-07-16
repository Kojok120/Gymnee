import SwiftUI

/// 共有カードの見た目（§6.6）。写真の上にサマリをオーバーレイ。ImageRenderer で画像化される。
struct ShareCardView: View {
    let content: ShareCardContent
    let theme: ShareCardTheme
    /// 基準サイズ（カード幅）。レンダリング時は scale で高解像度化する。
    var side: CGFloat = 360

    /// メニュー一覧の最大表示行数（超過分は「＋他N種目」に畳む）。
    static let maxLines = 10

    private var shownLineCount: Int {
        content.showExercises ? min(content.exerciseLines.count, Self.maxLines) : 0
    }

    /// カードの高さ。一覧が6行以下なら正方形、それ以上は行数に応じて縦長にする
    /// （maxLines 到達時に 4:5 ＝ Instagram フィードの縦長上限に収まる伸び幅）。
    private var cardHeight: CGFloat {
        side + CGFloat(max(0, shownLineCount - 6)) * side * 0.0625
    }

    var body: some View {
        ZStack {
            background
            if !theme.isTransparent {
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(theme == .light ? 0 : 0.7)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            content_overlay
                // 透過テンプレは下地が分からないので、文字に影を付けて可読性を担保。
                .shadow(color: theme.isTransparent ? .black.opacity(0.55) : .clear, radius: 4, y: 1)
        }
        .frame(width: side, height: cardHeight)
        .clipped()
    }

    @ViewBuilder
    private var background: some View {
        if theme.isTransparent {
            Color.clear   // 背景透過：ユーザーが自分の写真に重ねる
        } else if let image = content.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .overlay(theme.textColor == .black ? Color.white.opacity(theme.overlayOpacity) : Color.black.opacity(theme.overlayOpacity))
        } else {
            // 写真なし：単色グラデだけだと「真っ暗な空き地」に見えるため、
            // 薄い斜めストライプ＋透かしロゴで質感を足す（文字の可読性を損なわない濃度）。
            // ライトテーマは黒文字のため、下地も明るいグラデに切り替える。
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    colors: theme == .light
                        ? [.white, theme.accent.opacity(0.45)]
                        : [Theme.deep, theme.accent.opacity(0.6)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                DiagonalStripes()
                    .foregroundStyle(theme.textColor.opacity(0.045))
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: side * 0.55, weight: .bold))
                    .foregroundStyle(theme.accent.opacity(0.10))
                    .rotationEffect(.degrees(-12))
                    .offset(x: side * 0.16, y: side * 0.12)
            }
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
            if content.showExercises, !content.exerciseLines.isEmpty {
                Spacer(minLength: side * 0.04)
                exerciseList
            }
            Spacer()
            VStack(alignment: .leading, spacing: side * 0.025) {
                if content.showGym, let gym = content.gymName {
                    Label(gym, systemImage: "location.fill")
                        .font(.system(size: side * 0.05, weight: .bold))
                        .foregroundStyle(theme.textColor)
                }
                if !content.stats.isEmpty {
                    statRow
                } else if content.showExercises, let ex = content.exerciseSummary {
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

    /// 中央のメニュー一覧。1種目=1行（名前｜ベストセット・セット数）。最大 maxLines 件＋「他N種目」。
    private var exerciseList: some View {
        let shown = content.exerciseLines.prefix(Self.maxLines)
        return VStack(alignment: .leading, spacing: side * 0.024) {
            ForEach(shown) { line in
                HStack(spacing: side * 0.015) {
                    Text(line.name)
                        .font(.system(size: side * 0.042, weight: .semibold))
                        .foregroundStyle(theme.textColor)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if line.isPR {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: side * 0.032))
                            .foregroundStyle(theme.accent)
                    }
                    Spacer(minLength: side * 0.02)
                    Text(line.detail)
                        .font(.system(size: side * 0.036, weight: .medium).monospacedDigit())
                        .foregroundStyle(theme.textColor.opacity(0.85))
                        .lineLimit(1).fixedSize()
                }
            }
            if content.exerciseLines.count > shown.count {
                Text("＋他\(content.exerciseLines.count - shown.count)種目")
                    .font(.system(size: side * 0.034, weight: .medium))
                    .foregroundStyle(theme.textColor.opacity(0.7))
            }
        }
    }

    /// 下部のスタット行（総量・セット数・時間）。等幅に割り付ける。
    private var statRow: some View {
        HStack(spacing: 0) {
            ForEach(content.stats) { stat in
                VStack(alignment: .leading, spacing: side * 0.005) {
                    Text(stat.value)
                        .font(.system(size: side * 0.052, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(theme.textColor)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(stat.label)
                        .font(.system(size: side * 0.03, weight: .semibold))
                        .foregroundStyle(theme.textColor.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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

/// 写真なし背景用の斜めストライプ。foregroundStyle で色/濃度を指定する。
private struct DiagonalStripes: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 28
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            ctx.stroke(path, with: .style(.foreground), lineWidth: 9)
        }
    }
}
