import SwiftUI

// MARK: - Confetti burst（祝福レイヤー）

/// 依存ライブラリなしの軽量な紙吹雪。PR 更新など「やり切った瞬間」にだけ重ねて特別感を出す。
/// 出現時に一度だけ落下アニメを再生し、当たり判定は持たない（操作を邪魔しない）。
struct ConfettiView: View {
    var pieceCount: Int = 90

    @State private var animate = false
    private let pieces: [Piece]

    init(pieceCount: Int = 90) {
        self.pieceCount = pieceCount
        let palette: [Color] = [
            Theme.lime, Theme.limeBright,
            Color(hexF: 0xD8FF6B), Color(hexF: 0x8FD400),
            Theme.warning, .white,
        ]
        var rng = SystemRandomNumberGenerator()
        pieces = (0..<pieceCount).map { _ in
            Piece(
                x: .random(in: 0...1, using: &rng),
                delay: .random(in: 0...0.45, using: &rng),
                duration: .random(in: 1.4...2.6, using: &rng),
                drift: .random(in: -70...70, using: &rng),
                size: .random(in: 6...12, using: &rng),
                color: palette.randomElement(using: &rng) ?? Theme.lime,
                spin: .random(in: 1...4, using: &rng),
                isCircle: Bool.random(using: &rng)
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    Group {
                        if p.isCircle {
                            Circle().fill(p.color)
                        } else {
                            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(p.color)
                        }
                    }
                    .frame(width: p.size, height: p.size * (p.isCircle ? 1 : 1.6))
                    .rotationEffect(.degrees(animate ? p.spin * 360 : 0))
                    .position(
                        x: p.x * geo.size.width + (animate ? p.drift : 0),
                        y: animate ? geo.size.height + 40 : -40
                    )
                    .opacity(animate ? 0 : 1)
                    .animation(.easeIn(duration: p.duration).delay(p.delay), value: animate)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear { animate = true }
    }

    private struct Piece: Identifiable {
        let id = UUID()
        let x: CGFloat          // 0...1（横位置の割合）
        let delay: Double
        let duration: Double
        let drift: CGFloat      // 落下中の横ブレ(px)
        let size: CGFloat
        let color: Color
        let spin: Double        // 回転数
        let isCircle: Bool
    }
}

// MARK: - PR trophy badge（計測タイプ別トロフィー）

/// 計測タイプ別の獲得トロフィー。bouncy なオーバーシュートで「喜び」を演出し、
/// 出現時に index ごとにずらして連続して立ち上がる。祝福画面・実績で共用。
struct PRTrophyBadge: View {
    let type: PRType
    let value: Double
    var exerciseName: String?
    var index: Int = 0

    @State private var shown = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Theme.celebration)
                    .frame(width: 66, height: 66)
                    .shadow(color: Theme.limeGlow, radius: 14, y: 4)
                Image(systemName: type.symbol)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.onLime)
            }
            .scaleEffect(shown ? 1 : 0.2)
            .rotationEffect(.degrees(shown ? 0 : -28))

            Text(type.formatted(value))
                .font(.numS)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            if let exerciseName {
                Text(exerciseName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            OverlineLabel(text: type.label)
        }
        .frame(width: 104)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.bouncy.delay(0.15 + Double(index) * 0.12)) { shown = true }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: shown)
    }
}
