import SwiftUI

/// トレーニング完了直後に、育成タブで出す「この 1 回で何が育ったか」のまとめ。
///
/// 記録の完了サマリーではなく**キャラのいる部屋で出す**。育った本人を目の前にして
/// 説明するほうが、数字と姿がひとつに結びつく。
struct GrowthCelebrationSheet: View {
    let gain: WorkoutGrowth.Gain
    /// 姿。**進化段階は `gain.stageAfter` を使う**（集計の反映を待たずに出すため、
    /// 呼び出し側の derived から取ると進化した回に旧段階の姿を描いてしまう）。
    let look: PixelCharacterRenderer.Look

    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    /// 見出しを祝う回か（進化 or レベルアップ）。紙吹雪と触覚はこのときだけ。
    private var isBig: Bool { gain.didEvolve || gain.didLevelUp }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)

            figure

            VStack(spacing: Theme.Spacing.sm) {
                Text(WorkoutGrowth.headline(for: gain))
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(WorkoutGrowth.detail(for: gain))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            levelCard

            if let muscles = WorkoutGrowth.muscleSummary(for: gain) {
                Text(muscles)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            Button("いいね") { dismiss() }
                .buttonStyle(.gymneePrimary(fullWidth: true))
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg0)
        .overlay(alignment: .top) {
            if isBig && appeared { ConfettiView().transition(.opacity).allowsHitTesting(false) }
        }
        .onAppear { withAnimation(.smooth) { appeared = true } }
        .sensoryFeedback(isBig ? .success : .impact(weight: .light), trigger: appeared)
        .presentationDetents([.large])
    }

    /// 育った本人。進化した回は一段大きく出す。
    private var figure: some View {
        Canvas { context, size in
            let dot = max(1, (size.height / CGFloat(PixelCharacterArt.canvasHeight)).rounded(.down))
            PixelCharacterRenderer.draw(
                in: &context, look: look, frame: .standing, facing: .down,
                feet: CGPoint(x: size.width / 2, y: size.height - dot), dot: dot
            )
        }
        .frame(width: 140, height: 140)
        .scaleEffect(appeared ? 1 : 0.5)
        .animation(.bouncy, value: appeared)
    }

    /// レベルと進捗。**上がった回は前後を並べて出す**（何が変わったのかを一目にする）。
    private var levelCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                if gain.didLevelUp {
                    Text("Lv.\(gain.levelBefore.value)")
                        .font(.numS).foregroundStyle(Theme.textTertiary)
                    Image(systemName: "arrow.right")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
                Text("Lv.\(gain.levelAfter.value)")
                    .font(.numM).foregroundStyle(gain.didLevelUp ? Theme.lime : Theme.textPrimary)
                Spacer(minLength: 0)
                Text("+\(gain.exp) EXP")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.lime)
            }

            // 進捗はレベルアップの有無で意味が変わる。上がったなら「新しいレベルの進み具合」、
            // 上がっていないなら「前回からどれだけ伸びたか」を伸びるバーで見せる。
            ProgressView(value: appeared ? gain.levelAfter.progress : startProgress)
                .tint(Theme.lime)
                .animation(.smooth(duration: 0.9), value: appeared)

            if gain.energy > 0 {
                Label("テストステロンパワー +\(gain.energy)", systemImage: "bolt.heart.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let hint = WorkoutGrowth.nextStageHint(gain.nextStage) {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard()
    }

    /// バーの開始位置。レベルが上がった回は 0 から引き直す（前のレベルのバーから続けると
    /// 上がったことが伝わらない）。
    private var startProgress: Double {
        gain.didLevelUp ? 0 : gain.levelBefore.progress
    }
}
