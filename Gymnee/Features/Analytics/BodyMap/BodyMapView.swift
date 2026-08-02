import SwiftUI

/// 人体図 1 体分（正面 or 背面）。部位を **今週の達成度**で塗り分け、タップで親へ通知する。
///
/// 色の方針:
/// - 塗り＝今週どれだけ鍛えたか。記録するほど lime に染まる（lime＝達成・アクティブ。AGENTS.md）。
///   休むと消える疲労度を主役にしていた頃は、普段の画面が全身グレーで成果がどこにも映らなかった。
/// - 縁＝疲労。回復中＝`Theme.warning` / 疲労＝`Theme.danger` で、追い込んだ直後だけ輪郭が立つ。
struct BodyMapView: View {
    let face: BodyMapPaths.Face
    /// 部位 → 今週の達成度(0…1)。塗りの濃さ。
    let loadByMuscle: [MuscleGroup: Double]
    /// 部位 → 疲労度(0…1)。縁の色。
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
                // 描画順は元データのまま（順番を変えると解剖の重なりが崩れる）。
                ForEach(regions) { region in
                    if let muscle = region.muscle {
                        // 部位は Button にする。押し込み・ハプティクスが付くうえ、
                        // ScrollView 内でのスクロール中は押下が自動でキャンセルされる
                        // （自前の DragGesture で押下を取るとスクロールを奪ってしまう）。
                        // ラベル自体が塗られた図形なので、当たり判定は図形どおりに決まる
                        // （透明ビュー＋contentShape に頼らない）。
                        Button { onSelect(muscle) } label: {
                            RegionShape(paths: region.paths).fill(fill(for: muscle))
                        }
                        .buttonStyle(RegionButtonStyle(
                            paths: region.paths,
                            stroke: stroke(for: muscle),
                            lineWidth: lineWidth(for: muscle),
                            canvasSize: geo.size
                        ))
                        .accessibilityLabel(muscle.label)
                    } else {
                        // 装飾（頭・首・手足）。塗るだけでタップしない。
                        // 膝・首など部位に重なる装飾が手前に来るので、当たり判定は必ず抜く
                        // （抜かないと重なった部分が押せない死角になる）。
                        ForEach(Array(region.paths.enumerated()), id: \.offset) { _, path in
                            path.fill(fill(for: nil))
                            path.stroke(stroke(for: nil), lineWidth: 0.6)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .aspectRatio(BodyMapPaths.aspectRatio, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(face.label)の人体図")
    }

    private func fill(for muscle: MuscleGroup?) -> Color {
        guard let muscle else { return Theme.textTertiary.opacity(0.18) }   // 装飾（頭・首・手足）
        return Self.loadColor(for: loadByMuscle[muscle] ?? 0)
    }

    /// 筋の境界線。塗りが薄い（＝今週まだ）ときでも解剖の形が読めるよう常に描く。
    /// 疲労が乗っている部位はここで色を立て、「触ったばかり」を伝える。
    private func stroke(for muscle: MuscleGroup?) -> Color {
        guard let muscle else { return Theme.textTertiary.opacity(0.25) }
        if muscle == selected { return Theme.textPrimary }
        switch MuscleFatigue.level(for: fatigueByMuscle[muscle] ?? 0) {
        case .fatigued: return Theme.danger
        case .recovering: return Theme.warning
        case .recovered: return Theme.textTertiary.opacity(0.45)
        }
    }

    private func lineWidth(for muscle: MuscleGroup?) -> CGFloat {
        guard let muscle else { return 0.6 }
        if muscle == selected { return 1.6 }
        return MuscleFatigue.level(for: fatigueByMuscle[muscle] ?? 0) == .recovered ? 0.6 : 1.3
    }

    /// 今週の達成度 → 塗り色。0＝まだ手つかず（形だけ見える薄いグレー）、1＝目安到達（濃い lime）。
    /// 1 セットでも「色がついた」と分かるよう、下限側を持ち上げてから lime へ寄せる。
    static func loadColor(for progress: Double) -> Color {
        let p = progress.isFinite ? min(max(progress, 0), 1) : 0
        let empty = Theme.textTertiary.opacity(0.22)
        guard p > 0 else { return empty }
        return empty.mix(with: Theme.limeFill, by: 0.3 + 0.7 * p)
    }

    /// 疲労度 → 色（縁取り・部位詳細のインジケータ用）。
    /// 0（回復済み）はニュートラルなグレー、0.5 で `warning`、1 で `danger`。
    static func fatigueColor(for fatigue: Double) -> Color {
        let f = fatigue.isFinite ? min(max(fatigue, 0), 1) : 0
        let neutral = Theme.textTertiary.opacity(0.35)
        if f < 0.5 {
            return neutral.mix(with: Theme.warning, by: f / 0.5)
        }
        return Theme.warning.mix(with: Theme.danger, by: (f - 0.5) / 0.5)
    }
}

/// 部位 1 つぶんの描画とタップ。押している間だけ縮んで明るくし、押下でハプティクスを返す。
///
/// 「押せる」ことを見た目で伝えるのが目的なので、押下の表現は縮み **と** 明度の両方でやる。
/// 腕・体幹のような細い領域は縮みだけだとほとんど動いて見えないため。
private struct RegionButtonStyle: ButtonStyle {
    let paths: [Path]
    let stroke: Color
    let lineWidth: CGFloat
    /// 縮みの中心をその部位に置くための基準サイズ（人体図全体のサイズ）。
    let canvasSize: CGSize

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            configuration.label   // 部位の塗り。当たり判定もこの図形で決まる。
            RegionShape(paths: paths).stroke(stroke, lineWidth: lineWidth)
            RegionShape(paths: paths).fill(Theme.textPrimary.opacity(configuration.isPressed ? 0.16 : 0))
        }
        .scaleEffect(configuration.isPressed ? 0.97 : 1, anchor: anchor)
        .animation(.snappy, value: configuration.isPressed)
        // 指を置いた瞬間だけ返す（離した時にも鳴ると二度打ちに感じる）。
        .sensoryFeedback(trigger: configuration.isPressed) { _, pressed in
            pressed ? .impact(weight: .light) : nil
        }
    }

    /// 部位の中心。ここを軸に縮めないと、人体図全体が動いたように見える。
    private var anchor: UnitPoint {
        let box = paths.reduce(CGRect.null) { $0.union($1.boundingRect) }
        guard !box.isNull, box.midX.isFinite, box.midY.isFinite,
              canvasSize.width > 0, canvasSize.height > 0 else { return .center }
        return UnitPoint(x: box.midX / canvasSize.width, y: box.midY / canvasSize.height)
    }
}

/// 1 部位ぶんの複数パスをまとめた当たり判定シェイプ。
/// パスは人体図の座標系そのままなので `rect` は使わない。
private struct RegionShape: Shape {
    let paths: [Path]

    func path(in rect: CGRect) -> Path {
        var combined = Path()
        for sub in paths { combined.addPath(sub) }
        return combined
    }
}

/// 人体図の凡例。塗り＝今週の量（3段階）、縁＝疲労。
struct BodyMapLegend: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            legendDot(BodyMapView.loadColor(for: 0), "今週まだ")
            legendDot(BodyMapView.loadColor(for: 0.5), "途中")
            legendDot(BodyMapView.loadColor(for: 1), "目安到達")
            HStack(spacing: 5) {
                Circle().strokeBorder(Theme.warning, lineWidth: 1.5)
                    .frame(width: 9, height: 9)
                Text("回復中").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
