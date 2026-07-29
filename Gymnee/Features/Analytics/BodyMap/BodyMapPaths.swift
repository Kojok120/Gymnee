import SwiftUI

/// 人体図の筋群パス（正規化座標）。
///
/// 画像アセットや外部ライブラリに依存せず、**0…1 の正規化座標を持つ Swift 定数**として保持する。
/// - ベクターなので解像度非依存（Retina でも Widget でも同じコードで綺麗に出る）
/// - 塗り色を部位ごとに動的に変えられる（疲労度のグラデーション）
/// - タップ判定は `Path.contains(_:)` で図形どおりに取れる（矩形近似ではない）
///
/// 描画は「筋群ブロック」の集まりで、**塗りの単位は既存の `MuscleGroup`（8部位）**。
/// 解剖学的にはもっと細かい筋（三角筋・広背筋・大腿四頭筋…）を描き分けているが、
/// 色は所属する MuscleGroup で決まる。将来 MuscleGroup を細分化してもパス資産は使い回せる。
///
/// 座標系: x は 0=左端 / 1=右端、y は 0=頭頂 / 1=足先。人体は中央 (x=0.5) に左右対称で置く。
enum BodyMapPaths {

    /// 表示する面。
    enum Face: String, CaseIterable, Identifiable, Sendable {
        case front, back
        var id: String { rawValue }
        var label: String { self == .front ? "正面" : "背面" }
    }

    /// 1 つの筋群ブロック（描画順＝配列順）。
    struct Region: Identifiable {
        let id: String
        /// 塗り色を決める部位。nil＝装飾のみ（頭部など。タップも塗りもしない）。
        let muscle: MuscleGroup?
        /// 正規化座標(0…1)の閉じたパスを作る。
        let path: (CGRect) -> Path

        init(_ id: String, _ muscle: MuscleGroup?, path: @escaping (CGRect) -> Path) {
            self.id = id
            self.muscle = muscle
            self.path = path
        }
    }

    static func regions(for face: Face) -> [Region] {
        face == .front ? front : back
    }

    // MARK: - 作図ヘルパ（正規化座標 → 実座標）

    /// 正規化座標の点列から閉じた多角形を作る。角を丸めて「筋肉の塊」らしい輪郭にする。
    private static func poly(_ points: [(CGFloat, CGFloat)], rounding: CGFloat = 0.02) -> (CGRect) -> Path {
        { rect in
            let pts = points.map { CGPoint(x: rect.minX + $0.0 * rect.width, y: rect.minY + $0.1 * rect.height) }
            guard pts.count > 2 else { return Path() }
            let r = rounding * min(rect.width, rect.height)
            var path = Path()
            for i in 0..<pts.count {
                let prev = pts[(i - 1 + pts.count) % pts.count]
                let curr = pts[i]
                let next = pts[(i + 1) % pts.count]
                let start = point(from: curr, toward: prev, distance: r)
                let end = point(from: curr, toward: next, distance: r)
                if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
                path.addQuadCurve(to: end, control: curr)
            }
            path.closeSubpath()
            return path
        }
    }

    /// `point` から `other` の方向へ `distance` だけ進んだ位置（角丸の始点/終点）。
    private static func point(from point: CGPoint, toward other: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = other.x - point.x, dy = other.y - point.y
        let len = max(sqrt(dx * dx + dy * dy), 0.0001)
        let t = min(distance / len, 0.45)
        return CGPoint(x: point.x + dx * t, y: point.y + dy * t)
    }

    /// 正規化座標の楕円。
    private static func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> (CGRect) -> Path {
        { rect in
            Path(ellipseIn: CGRect(
                x: rect.minX + (cx - rx) * rect.width,
                y: rect.minY + (cy - ry) * rect.height,
                width: rx * 2 * rect.width,
                height: ry * 2 * rect.height
            ))
        }
    }

    /// 左半身の定義を右半身へ反転する（人体は左右対称なので片側だけ書けばよい）。
    private static func mirrored(_ points: [(CGFloat, CGFloat)]) -> [(CGFloat, CGFloat)] {
        points.map { (1 - $0.0, $0.1) }
    }

    // MARK: - 正面

    static let front: [Region] = {
        // 画面向かって左＝本人の右。肩は広く、腰はくびれ、四肢は先細りさせる。
        let deltoid: [(CGFloat, CGFloat)] = [
            (0.300, 0.212), (0.372, 0.192), (0.398, 0.232), (0.386, 0.276), (0.322, 0.282), (0.292, 0.250),
        ]
        let pec: [(CGFloat, CGFloat)] = [
            (0.404, 0.212), (0.492, 0.208), (0.492, 0.288), (0.416, 0.284), (0.392, 0.248),
        ]
        let biceps: [(CGFloat, CGFloat)] = [
            (0.294, 0.284), (0.352, 0.288), (0.346, 0.372), (0.292, 0.376), (0.282, 0.330),
        ]
        let forearm: [(CGFloat, CGFloat)] = [
            (0.292, 0.382), (0.344, 0.380), (0.334, 0.478), (0.290, 0.480),
        ]
        let abs: [(CGFloat, CGFloat)] = [
            (0.424, 0.296), (0.492, 0.296), (0.492, 0.436), (0.432, 0.432), (0.418, 0.360),
        ]
        let oblique: [(CGFloat, CGFloat)] = [
            (0.398, 0.300), (0.422, 0.298), (0.430, 0.430), (0.404, 0.412), (0.392, 0.352),
        ]
        let quad: [(CGFloat, CGFloat)] = [
            (0.406, 0.470), (0.492, 0.470), (0.492, 0.652), (0.428, 0.656), (0.400, 0.560),
        ]
        let calf: [(CGFloat, CGFloat)] = [
            (0.424, 0.678), (0.486, 0.678), (0.480, 0.838), (0.436, 0.840), (0.420, 0.760),
        ]

        var regions: [Region] = [
            Region("head", nil, path: oval(0.5, 0.078, 0.058, 0.066)),
            Region("neck", nil, path: poly([(0.468, 0.136), (0.532, 0.136), (0.540, 0.190), (0.460, 0.190)])),
        ]
        func pair(_ id: String, _ muscle: MuscleGroup, _ pts: [(CGFloat, CGFloat)]) {
            regions.append(Region("\(id).l", muscle, path: poly(pts)))
            regions.append(Region("\(id).r", muscle, path: poly(mirrored(pts))))
        }
        pair("deltoid", .shoulders, deltoid)
        pair("pec", .chest, pec)
        pair("biceps", .arms, biceps)
        pair("forearm", .arms, forearm)
        pair("abs", .abs, abs)
        pair("oblique", .core, oblique)
        pair("quad", .legs, quad)
        pair("calf", .legs, calf)
        return regions
    }()

    // MARK: - 背面

    static let back: [Region] = {
        let rearDelt: [(CGFloat, CGFloat)] = [
            (0.300, 0.212), (0.372, 0.192), (0.398, 0.232), (0.386, 0.276), (0.322, 0.282), (0.292, 0.250),
        ]
        let trap: [(CGFloat, CGFloat)] = [
            (0.404, 0.190), (0.492, 0.186), (0.492, 0.262), (0.418, 0.252), (0.392, 0.216),
        ]
        let lat: [(CGFloat, CGFloat)] = [
            (0.396, 0.268), (0.492, 0.272), (0.492, 0.388), (0.428, 0.380), (0.390, 0.320),
        ]
        let lowerBack: [(CGFloat, CGFloat)] = [
            (0.428, 0.394), (0.492, 0.394), (0.492, 0.452), (0.432, 0.448),
        ]
        let triceps: [(CGFloat, CGFloat)] = [
            (0.294, 0.284), (0.352, 0.288), (0.346, 0.372), (0.292, 0.376), (0.282, 0.330),
        ]
        let forearm: [(CGFloat, CGFloat)] = [
            (0.292, 0.382), (0.344, 0.380), (0.334, 0.478), (0.290, 0.480),
        ]
        let glute: [(CGFloat, CGFloat)] = [
            (0.406, 0.462), (0.492, 0.462), (0.492, 0.552), (0.412, 0.548), (0.398, 0.500),
        ]
        let hamstring: [(CGFloat, CGFloat)] = [
            (0.410, 0.560), (0.492, 0.560), (0.492, 0.664), (0.428, 0.666), (0.404, 0.610),
        ]
        let calf: [(CGFloat, CGFloat)] = [
            (0.424, 0.686), (0.486, 0.686), (0.480, 0.842), (0.436, 0.844), (0.420, 0.766),
        ]

        var regions: [Region] = [
            Region("head", nil, path: oval(0.5, 0.078, 0.058, 0.066)),
            Region("neck", nil, path: poly([(0.468, 0.136), (0.532, 0.136), (0.540, 0.190), (0.460, 0.190)])),
        ]
        func pair(_ id: String, _ muscle: MuscleGroup, _ pts: [(CGFloat, CGFloat)]) {
            regions.append(Region("\(id).l", muscle, path: poly(pts)))
            regions.append(Region("\(id).r", muscle, path: poly(mirrored(pts))))
        }
        pair("reardelt", .shoulders, rearDelt)
        pair("trap", .back, trap)
        pair("lat", .back, lat)
        pair("lowerback", .core, lowerBack)
        pair("triceps", .arms, triceps)
        pair("forearm", .arms, forearm)
        pair("glute", .glutes, glute)
        pair("hamstring", .legs, hamstring)
        pair("calf", .legs, calf)
        return regions
    }()

    /// 体のシルエット（筋群の下に敷く輪郭）。
    /// 反時計回りに「首→左肩→左腕→左脚→（中央）→右脚→右腕→右肩」と一周する。
    static func silhouette(_ face: Face) -> (CGRect) -> Path {
        // 正面/背面でシルエットは共通（塗り分けだけが変わる）。
        _ = face
        let half: [(CGFloat, CGFloat)] = [
            (0.458, 0.140),                       // 首の付け根
            (0.386, 0.180), (0.300, 0.198),       // 僧帽 → 肩
            (0.278, 0.240), (0.276, 0.300),       // 三角筋の外縁
            (0.272, 0.390), (0.276, 0.490),       // 上腕 → 前腕
            (0.302, 0.500), (0.330, 0.410),       // 手首 → 内側へ折り返し
            (0.352, 0.300), (0.386, 0.280),       // 脇
            (0.394, 0.330), (0.398, 0.400),       // くびれ（腰）
            (0.392, 0.452),                       // 骨盤
            (0.396, 0.560), (0.412, 0.670),       // 大腿 → 膝
            (0.418, 0.760), (0.428, 0.870),       // 下腿 → 足首
            (0.470, 0.884), (0.478, 0.700),       // 足 → 内側へ折り返し
            (0.492, 0.560), (0.500, 0.470),       // 内股 → 股間（中央）
        ]
        let points = half + mirrored(half).reversed()
        return poly(points, rounding: 0.016)
    }
}
