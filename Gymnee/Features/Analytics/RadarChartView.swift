import SwiftUI

/// 部位バランスのレーダーチャート（§6.8）。値は 0〜1 に正規化して渡す。
struct RadarChartView: View {
    /// (ラベル, 正規化値0...1, 実値表示文字列)
    let data: [(label: String, value: Double, display: String)]
    var tint: Color = Theme.energy

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2 * 0.72
            let n = max(data.count, 3)

            ZStack {
                // グリッド（同心多角形）
                ForEach(1...4, id: \.self) { ring in
                    polygon(center: center, radius: radius * CGFloat(ring) / 4, count: n)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }
                // 軸
                ForEach(0..<n, id: \.self) { i in
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: point(center: center, radius: radius, index: i, count: n))
                    }
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }
                // データ多角形
                dataPath(center: center, radius: radius)
                    .fill(tint.opacity(0.25))
                dataPath(center: center, radius: radius)
                    .stroke(tint, lineWidth: 2)
                // ラベル
                ForEach(0..<data.count, id: \.self) { i in
                    let pt = point(center: center, radius: radius * 1.16, index: i, count: n)
                    Text(data[i].label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(pt)
                }
            }
        }
    }

    private func dataPath(center: CGPoint, radius: CGFloat) -> Path {
        Path { p in
            for i in 0..<data.count {
                let r = radius * CGFloat(max(0, min(data[i].value, 1)))
                let pt = point(center: center, radius: r, index: i, count: max(data.count, 3))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }

    private func polygon(center: CGPoint, radius: CGFloat, count: Int) -> Path {
        Path { p in
            for i in 0..<count {
                let pt = point(center: center, radius: radius, index: i, count: count)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }

    private func point(center: CGPoint, radius: CGFloat, index: Int, count: Int) -> CGPoint {
        let angle = (Double(index) / Double(count)) * 2 * .pi - .pi / 2
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
    }
}
