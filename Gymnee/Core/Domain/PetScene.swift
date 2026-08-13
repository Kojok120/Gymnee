import Foundation

/// 部屋のペットの居場所と動き（純粋計算）。
///
/// キャラと同じく**状態を持たず時刻から決定的に導出**する（`CharacterScene` と同じ流儀）。
/// 保存も常駐処理も要らないので、バックグラウンドから戻っても位置が飛ばない。
///
/// ペットは**飼い主について回る**。独立に徘徊させると「もう 1 人いる」ように見えてペットにならない。
/// `CharacterScene.pose(at:seed:)` が時刻の純粋関数なので、
/// **「少し前の飼い主の位置」を目標にするだけ**で追従が書ける。
enum PetScene {

    /// 何秒ぶん遅れてついていくか。大きいほど「離れてついてくる」ように見える。
    static let followDelay: TimeInterval = 1.1

    /// 飼い主の横にどれだけずらすか（正規化座標）。
    ///
    /// **必ず横にずらす**。真下に重ねるとペットがキャラの脚を隠してしまう
    /// （小さいぶん手前に描かれるので、重なると主役が隠れる）。
    static let sideOffset: Double = 0.17

    /// 飼い主より少し手前に立たせる量。手前に置くと重なり順が安定し、ペットが背中に埋もれない。
    static let depthOffset: Double = 0.05

    /// 飼い主から離れる最大距離。追従が効いているかの判定に使う。
    static var followRadius: Double { (sideOffset * sideOffset + depthOffset * depthOffset).squareRoot() }

    /// この距離未満しか動いていなければ、歩かずに座る。
    /// 数ドットの移動で歩行アニメが出ると足踏みして見えるため（`CharacterScene.minimumWalkDistance` と同じ考え）。
    static let settleDistance: Double = 0.012

    /// 歩幅が小さいぶん、キャラより速く足を動かす。
    static let stepsPerSecond: Double = 3.2

    /// 向きの判定に使う、ひとつ前を見る時間。
    private static let velocitySample: TimeInterval = 0.25

    /// 撫でられたときの反応の長さ。`TapReaction.duration` に合わせる。
    static let reactionDuration: TimeInterval = TapReaction.duration

    enum Behavior: Equatable, Sendable {
        case walking
        case sitting
        /// 撫でられて喜んでいる。
        case happy
    }

    /// ある時刻のペットの姿勢。
    struct Pose: Equatable, Sendable {
        /// 立ち位置。`CharacterScene.Pose.position` と同じ正規化座標（y は 0＝奥 / 1＝手前）。
        var position: CGPoint
        var facing: CharacterScene.Facing
        var behavior: Behavior
        /// 歩行サイクルの位相（0...1）。
        var walkPhase: Double
        /// 整数ドットの上下。歩きと喜びの弾みをここで表す。
        var bob: Int
        var blink: Bool
    }

    /// 留守番の位置。飼い主が遠征に出ている間はドアの近くで待つ。
    /// 待っている姿そのものが「いま遠征中」の説明になる。
    static let waitSpot = CGPoint(
        x: ExpeditionDeparture.doorSpot.x - 0.10,
        y: ExpeditionDeparture.doorSpot.y + 0.14
    )

    /// 指定時刻のペットの姿勢。
    ///
    /// - Parameters:
    ///   - ownerSeed: 飼い主の歩き方のシード（`CharacterScene.pose` に渡すもの）。
    ///   - seed: ペット個体のシード。ずらす向きと、まばたきの間隔を変える。
    ///   - ownerAway: 飼い主が遠征に出ていて部屋にいないか。
    static func pose(at time: TimeInterval, ownerSeed: UInt64, seed: UInt64, ownerAway: Bool) -> Pose {
        let t = max(0, time)
        guard !ownerAway else {
            return Pose(
                position: waitSpot,
                facing: .down,
                behavior: .sitting,
                walkPhase: 0,
                bob: 0,
                blink: blink(at: t, seed: seed)
            )
        }

        let offset = offset(seed: seed)
        let now = follow(at: t, ownerSeed: ownerSeed, offset: offset)
        let before = follow(at: t - velocitySample, ownerSeed: ownerSeed, offset: offset)
        let moved = distance(before, now)

        guard moved >= settleDistance else {
            return Pose(
                position: now,
                // 止まったらこちらを向いて座る。飼い主に背を向けたまま止まると置物に見える。
                facing: .down,
                behavior: .sitting,
                walkPhase: 0,
                bob: 0,
                blink: blink(at: t, seed: seed)
            )
        }

        let phase = (t * stepsPerSecond).truncatingRemainder(dividingBy: 1)
        return Pose(
            position: now,
            facing: CharacterScene.facing(from: before, to: now),
            behavior: .walking,
            walkPhase: phase,
            // 歩くたび 1 ドットだけ跳ねる。小さい生き物はこれだけで生きて見える。
            bob: phase < 0.5 ? 1 : 0,
            blink: blink(at: t, seed: seed)
        )
    }

    /// 撫でられたときの姿勢。**位置は動かさず**、こちらを向いて弾む。
    /// 反応中に歩き出すと、撫でた指から逃げたように見えてしまう。
    static func reactingPose(base: Pose, elapsed: TimeInterval) -> Pose? {
        guard elapsed >= 0, elapsed <= reactionDuration else { return nil }
        var pose = base
        pose.behavior = .happy
        pose.facing = .down
        pose.walkPhase = 0
        // 2 回ぶん跳ねる。
        let progress = elapsed / reactionDuration
        pose.bob = sin(progress * 4 * .pi) > 0 ? 2 : 0
        pose.blink = false
        return pose
    }

    /// 少し前の飼い主の位置に、個体ごとのずらしを足したもの。
    private static func follow(at time: TimeInterval, ownerSeed: UInt64, offset: CGPoint) -> CGPoint {
        let owner = CharacterScene.pose(at: max(0, time - followDelay), seed: ownerSeed).position
        return clamp(CGPoint(x: owner.x + offset.x, y: owner.y + offset.y))
    }

    /// 個体ごとのずらし。飼い主の斜め前（左右どちらか）に並ばせる。
    private static func offset(seed: UInt64) -> CGPoint {
        var rng = DeterministicRandom(seed: seed &+ 0x5BF0_3635)
        return CGPoint(x: rng.unit() < 0.5 ? sideOffset : -sideOffset, y: depthOffset)
    }

    /// 歩ける範囲はキャラと同じ。端で見切れさせない。
    private static func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(Double(point.x), CharacterScene.xRange.lowerBound), CharacterScene.xRange.upperBound),
            y: min(max(Double(point.y), CharacterScene.yRange.lowerBound), CharacterScene.yRange.upperBound)
        )
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// まばたき。個体ごとに間隔をずらして、飼い主と同時に閉じないようにする。
    private static func blink(at time: TimeInterval, seed: UInt64) -> Bool {
        let period = 4.3 + Double(seed % 7) * 0.4
        let phase = time.truncatingRemainder(dividingBy: period)
        return phase < 0.16
    }
}
