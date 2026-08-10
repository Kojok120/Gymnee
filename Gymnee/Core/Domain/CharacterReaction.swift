import CoreGraphics
import Foundation

/// キャラをタップしたときの反応（純粋関数）。
///
/// コーチが居ない間、画面を触っても何も起きないと部屋が死んで見える。
/// 進行には一切影響しない**触れば返事が返ってくるだけ**の反応を置く（強さは現実でしか変わらない、を崩さない）。
enum CharacterReaction {

    /// 反応が続く時間（秒）。
    static let duration: TimeInterval = 1.1

    /// タップの当たり判定の半径。画枠（24 ドット）に対する割合で、指で狙える程度に広めに取る。
    static let hitRadiusRatio: Double = 0.75

    /// 浮かべる絵。同じ反応の繰り返しに見えないよう、タップのたびに変える。
    enum Particle: Int, CaseIterable, Sendable {
        case heart, note, sparkle

        /// タップの回数から次の絵を選ぶ。
        static func next(count: Int) -> Particle {
            allCases[abs(count) % allCases.count]
        }
    }

    /// タップがキャラに当たったか。座標はどちらも画面座標（pt）。
    /// `size` はキャラの表示上の一辺（＝画枠 24 ドット分の pt）。
    static func isHit(tap: CGPoint, feet: CGPoint, size: CGFloat) -> Bool {
        guard size > 0 else { return false }
        // 足元を基準に、頭のてっぺんまでを含む箱で判定する。
        let half = size * hitRadiusRatio / 2
        let box = CGRect(
            x: feet.x - half,
            y: feet.y - size,
            width: half * 2,
            height: size
        )
        return box.insetBy(dx: -size * 0.1, dy: -size * 0.1).contains(tap)
    }

    /// 反応中の姿勢。位置と向きは元のまま保ち、仕草だけ差し替える。
    /// 反応が終わっていれば nil（呼び出し側は元の姿勢をそのまま使う）。
    static func pose(base: CharacterScene.Pose, elapsed: TimeInterval) -> CharacterScene.Pose? {
        guard elapsed >= 0, elapsed < duration else { return nil }
        var pose = base
        pose.behavior = .emoting(.cheer)
        pose.walkPhase = 0
        // 反応時間いっぱいで 1 周期。跳ねて着地するまでを見せる。
        pose.emotePhase = min(1, elapsed / duration)
        // 触られたらこちらを向く。
        pose.facing = .down
        return pose
    }

    /// 浮かぶ絵の進み具合（0＝出た瞬間 / 1＝消える直前）。反応が終わっていれば nil。
    static func particleProgress(elapsed: TimeInterval) -> Double? {
        guard elapsed >= 0, elapsed < duration else { return nil }
        return min(1, elapsed / duration)
    }

    /// 浮かぶ絵の不透明度。最後だけ急に消えないよう、後半でなめらかに引く。
    static func particleOpacity(progress: Double) -> Double {
        let p = min(1, max(0, progress))
        guard p > 0.55 else { return 1 }
        return max(0, 1 - (p - 0.55) / 0.45)
    }

    /// 浮かぶ絵が上がる高さ（キャラの一辺に対する割合）。
    static func particleRise(progress: Double) -> Double {
        let p = min(1, max(0, progress))
        // 出だしを速く、上ほど緩やかに。
        return 0.55 * (1 - (1 - p) * (1 - p))
    }
}
