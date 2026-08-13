import CoreGraphics
import Foundation

/// 部屋のものを触ったときの反応（純粋関数）。
///
/// 画面を触っても何も起きないと部屋が死んで見える。進行には一切影響しない
/// **触れば返事が返ってくるだけ**の反応を置く（強さは現実でしか変わらない、を崩さない）。
///
/// キャラ本体のタップは「からだ」（人体図）を開くのに使うので、
/// ハート・音符・きらめきの反応は**ペットの役目**になった。
/// 対象ごとに `State` を 1 つ持たせれば、何体いても同じ仕組みで反応させられる。
enum TapReaction {

    /// 反応が続く時間（秒）。
    static let duration: TimeInterval = 1.1

    /// タップの当たり判定の半径。画枠に対する割合。
    static let hitRadiusRatio: Double = 0.75

    /// ペットの当たり判定。絵が 16 ドットとキャラの 2/3 しかないので、指で狙える幅まで広げる。
    static let petHitRadiusRatio: Double = 1.15

    /// 浮かべる絵。同じ反応の繰り返しに見えないよう、タップのたびに変える。
    enum Particle: Int, CaseIterable, Sendable {
        case heart, note, sparkle

        /// タップの回数から次の絵を選ぶ。
        static func next(count: Int) -> Particle {
            allCases[abs(count) % allCases.count]
        }
    }

    /// タップの反応の状態。**対象ごとに 1 つ**持つ。
    struct State: Equatable, Sendable {
        /// 最後に触られた時刻。まだ触られていなければ nil。
        var at: Date?
        var particle: Particle = .heart
        var count = 0

        /// 触られた。絵を次に進めて時刻を記録する。
        mutating func fire(now: Date = .now) {
            count += 1
            particle = .next(count: count)
            at = now
        }

        /// 反応が始まってからの経過時間。触られていなければ nil。
        func elapsed(_ now: Date) -> TimeInterval? {
            at.map { now.timeIntervalSince($0) }
        }
    }

    /// タップが当たったか。座標はどちらも画面座標（pt）。
    /// `size` は対象の表示上の一辺（＝画枠のドット数 × dot）。
    static func isHit(tap: CGPoint, feet: CGPoint, size: CGFloat, radiusRatio: Double = hitRadiusRatio) -> Bool {
        guard size > 0 else { return false }
        // 足元を基準に、頭のてっぺんまでを含む箱で判定する。
        let half = size * radiusRatio / 2
        let box = CGRect(
            x: feet.x - half,
            y: feet.y - size,
            width: half * 2,
            height: size
        )
        return box.insetBy(dx: -size * 0.1, dy: -size * 0.1).contains(tap)
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

    /// 浮かぶ絵が上がる高さ（対象の一辺に対する割合）。
    static func particleRise(progress: Double) -> Double {
        let p = min(1, max(0, progress))
        // 出だしを速く、上ほど緩やかに。
        return 0.55 * (1 - (1 - p) * (1 - p))
    }
}
