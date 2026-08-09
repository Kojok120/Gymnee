import SwiftUI

/// 進化段階を表すキャラの姿。段階が上がるほど輪が増え、色と記章が変わる（節目で「激変」させる担当）。
struct CharacterAvatarView: View {
    let stage: CharacterProgress.Stage
    /// 次のレベルまでの進捗（外周リング）。
    let levelProgress: Double
    var size: CGFloat = 132

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.bg3, lineWidth: 8)

            Circle()
                .trim(from: 0, to: max(0.001, min(1, levelProgress)))
                .stroke(Theme.streakRing, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(stageGradient)
                .padding(16)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        .padding(16)
                }

            Image(systemName: stage.symbol)
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.limeGlow, radius: stage >= .veteran ? 24 : 0)
        .accessibilityElement()
        .accessibilityLabel("\(stage.title)のキャラクター")
    }

    /// 段階ごとの色。上位ほど暖色〜金色に寄せ、一目で「変わった」と分かるようにする。
    private var stageGradient: LinearGradient {
        let colors: [Color]
        switch stage {
        case .rookie: colors = [Color(hexF: 0x5A6152), Color(hexF: 0x373C34)]
        case .trainee: colors = [Color(hexF: 0x4ECBFF), Color(hexF: 0x1E6E93)]
        case .challenger: colors = [Color(hexF: 0xB388FF), Color(hexF: 0x5C3BBF)]
        case .veteran: colors = [Color(hexF: 0xC6FF3D), Color(hexF: 0x5FA000)]
        case .champion: colors = [Color(hexF: 0xFFB23E), Color(hexF: 0xB35C00)]
        case .legend: colors = [Color(hexF: 0xFFE082), Color(hexF: 0xE0A100), Color(hexF: 0xFF8A5B)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

#Preview {
    HStack(spacing: 12) {
        CharacterAvatarView(stage: .rookie, levelProgress: 0.2, size: 90)
        CharacterAvatarView(stage: .veteran, levelProgress: 0.7, size: 90)
        CharacterAvatarView(stage: .legend, levelProgress: 0.95, size: 90)
    }
    .padding()
    .background(Theme.bg0)
}
