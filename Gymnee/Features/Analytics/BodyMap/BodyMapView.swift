import SwiftUI

/// 人体図 1 体分（正面 or 背面）。部位を疲労度で塗り分け、タップで親へ通知する。
///
/// 色の方針: 予約アクセントの lime は「達成・アクティブ」専用（AGENTS.md）なので疲労度には使わない。
/// 回復済み＝ニュートラル → 回復中＝`Theme.warning` → 疲労＝`Theme.danger` のグラデーションで表す。
struct BodyMapView: View {
    let face: BodyMapPaths.Face
    /// 部位 → 疲労度(0…1)。
    let fatigueByMuscle: [MuscleGroup: Double]
    /// 選択中の部位（強調表示）。
    var selected: MuscleGroup?
    var onSelect: (MuscleGroup) -> Void

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            // 領域の組み立て（パス解析＋座標変換）は毎フレームやると重いので 1 回にまとめる。
            let regions = BodyMapPaths.regions(for: face, in: rect)
            ZStack {
                ForEach(regions) { region in
                    ForEach(Array(region.paths.enumerated()), id: \.offset) { _, path in
                        path.fill(fill(for: region.muscle))
                        path.stroke(stroke(for: region.muscle), lineWidth: region.muscle == selected ? 1.6 : 0.6)
                    }
                }
            }
            .contentShape(Rectangle())
            // 図形どおりの当たり判定。矩形近似だと隣の部位に漏れるため Path.contains を使う。
            .onTapGesture { location in
                guard let muscle = BodyMapPaths.muscle(at: location, face: face, in: rect) else { return }
                onSelect(muscle)
            }
        }
        .aspectRatio(BodyMapPaths.aspectRatio, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(face.label)の人体図")
    }

    private func fill(for muscle: MuscleGroup?) -> Color {
        guard let muscle else { return Theme.textTertiary.opacity(0.18) }   // 装飾（頭・首・手足）
        return Self.color(for: fatigueByMuscle[muscle] ?? 0)
    }

    /// 筋の境界線。塗りが薄い（＝回復済み）ときでも解剖の形が読めるよう常に描く。
    private func stroke(for muscle: MuscleGroup?) -> Color {
        guard let muscle else { return Theme.textTertiary.opacity(0.25) }
        if muscle == selected { return Theme.textPrimary }
        return Theme.textTertiary.opacity(0.45)
    }

    /// 疲労度 → 色。
    /// 0（回復済み）はニュートラルなグレー、0.5 で `warning`、1 で `danger`。
    /// 予約アクセントの lime は「達成・アクティブ」専用なので使わない（AGENTS.md）。
    /// 回復済みでも「そこに筋肉がある」ことが見えるよう、下限は透明にしない。
    static func color(for fatigue: Double) -> Color {
        let f = fatigue.isFinite ? min(max(fatigue, 0), 1) : 0
        let neutral = Theme.textTertiary.opacity(0.35)
        if f < 0.5 {
            return neutral.mix(with: Theme.warning, by: f / 0.5)
        }
        return Theme.warning.mix(with: Theme.danger, by: (f - 0.5) / 0.5)
    }
}

/// 疲労度の凡例（3段階）。色の意味を 1 行で示す。
struct BodyMapLegend: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(MuscleFatigue.Level.allCases, id: \.self) { level in
                HStack(spacing: 5) {
                    Circle().fill(BodyMapView.color(for: representativeFatigue(level)))
                        .frame(width: 9, height: 9)
                    Text(level.label).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func representativeFatigue(_ level: MuscleFatigue.Level) -> Double {
        switch level {
        case .recovered: return 0
        case .recovering: return 0.35
        case .fatigued: return 0.85
        }
    }
}
