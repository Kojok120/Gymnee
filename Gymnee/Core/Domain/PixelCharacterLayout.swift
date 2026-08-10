import Foundation

/// ドット絵キャラの体格（純粋計算）。
///
/// ドット絵は連続的に太らせられないので、現実の記録を**段階に丸めて**パーツを選ぶ。
/// 胴 3 種 × 腕 2 種 × 脚 2 種 ＝ 12 通りの体型があり、記録が伸びると段階が上がる。
struct CharacterBuild: Equatable, Sendable {

    /// 胴の太さ。
    enum Girth: Int, CaseIterable, Sendable {
        case slim, normal, wide
    }

    /// 手足の太さ。
    enum Limb: Int, CaseIterable, Sendable {
        case thin, thick
    }

    var girth: Girth
    var arm: Limb
    var leg: Limb

    /// 体格パラメータ（0...1）から段階を選ぶ。
    /// しきい値は「記録を始めてすぐ 1 段階目が上がる」ようやや低めに置き、変化を早く体感させる。
    static func make(from appearance: CharacterAppearance) -> CharacterBuild {
        CharacterBuild(
            girth: girth(for: max(appearance.shoulder, appearance.torso)),
            arm: appearance.arm >= 0.55 ? .thick : .thin,
            leg: appearance.leg >= 0.55 ? .thick : .thin
        )
    }

    private static func girth(for value: Double) -> Girth {
        guard value.isFinite else { return .slim }
        if value >= 0.70 { return .wide }
        if value >= 0.48 { return .normal }
        return .slim
    }
}

/// 姿勢 → パーツごとの**整数ドット**のずらし量（純粋計算）。
///
/// ドット絵は整数位置にしか置けない。小数で動かすとアンチエイリアスでにじみ、ドット絵に見えなくなる。
/// そのため角度ではなく「何ドットずらすか」で全部を表現する。
enum PixelCharacterLayout {

    /// 1 コマ分のずらし量。単位はすべてドット、負＝上 / 左。
    struct Frame: Equatable, Sendable {
        /// 体（頭・胴・腕）全体の上下。
        var lift: Int
        /// 腰の落ち込み（しゃがみ）。脚は接地したまま体だけ沈む。
        var crouch: Int
        /// 腕の左右のずらし（振り）。
        var leftArmX: Int
        var rightArmX: Int
        /// 腕の上下。
        var leftArmY: Int
        var rightArmY: Int
        /// 腕を肩より上に構えるか（伸び・ガッツポーズ）。
        var armsRaised: Bool
        /// 脚の持ち上げ。
        var leftLegLift: Int
        var rightLegLift: Int
        /// 手にダンベルを持つ。
        var holdsDumbbell: Bool
        /// 目を閉じている。
        var blinking: Bool

        static let standing = Frame(
            lift: 0, crouch: 0,
            leftArmX: 0, rightArmX: 0, leftArmY: 0, rightArmY: 0, armsRaised: false,
            leftLegLift: 0, rightLegLift: 0,
            holdsDumbbell: false, blinking: false
        )
    }

    /// 歩行のコマ数。接地 → 左足上げ → 接地 → 右足上げ の 4 コマ。
    static let walkFrameCount = 4

    static func frame(for pose: CharacterScene.Pose) -> Frame {
        var frame = Frame.standing
        frame.blinking = pose.blink > 0.5

        switch pose.behavior {
        case .walking:
            applyWalk(&frame, phase: pose.walkPhase)
        case .emoting(let emote):
            apply(emote, to: &frame, phase: pose.emotePhase, breath: pose.breathPhase)
        }
        return frame
    }

    /// 歩行コマの番号（0...3）。
    static func walkFrameIndex(phase: Double) -> Int {
        guard phase.isFinite else { return 0 }
        let wrapped = phase - phase.rounded(.down)
        let index = Int(wrapped * Double(walkFrameCount))
        return min(walkFrameCount - 1, max(0, index))
    }

    private static func applyWalk(_ frame: inout Frame, phase: Double) {
        switch walkFrameIndex(phase: phase) {
        case 1:
            // 左足が上がり、体が 1 ドット浮く。腕は右が前に出る。
            frame.lift = -1
            frame.leftLegLift = 2
            frame.leftArmX = 1
            frame.rightArmX = -1
        case 3:
            frame.lift = -1
            frame.rightLegLift = 2
            frame.leftArmX = -1
            frame.rightArmX = 1
        default:
            // 接地コマ。
            break
        }
    }

    private static func apply(_ emote: CharacterScene.Emote, to frame: inout Frame, phase: Double, breath: Double) {
        switch emote {
        case .rest:
            // 呼吸。1 ドットだけ上下させる（これが無いと置物に見える）。
            frame.lift = breath > 0.35 ? -1 : 0

        case .squat:
            // 足は着けたまま腰を落とす。
            let depth = (1 - cos(clampedPhase(phase) * 2 * .pi)) / 2
            frame.crouch = Int((depth * 3).rounded())
            frame.leftArmY = -frame.crouch
            frame.rightArmY = -frame.crouch

        case .stretch:
            // 前半で腕を挙げ、後半で下ろす。
            let raise = sin(clampedPhase(phase) * .pi)
            frame.armsRaised = raise > 0.35
            frame.lift = raise > 0.7 ? -1 : 0

        case .curl:
            // 肩から前へ持ち上げる。2 段階だけ動かせば十分に読める。
            let lift = (1 - cos(clampedPhase(phase) * 2 * .pi)) / 2
            let step = Int((lift * 3).rounded())
            frame.leftArmY = -step
            frame.rightArmY = -step
            frame.holdsDumbbell = true

        case .cheer:
            // 万歳しながら跳ねる。
            frame.armsRaised = true
            let hop = sin(clampedPhase(phase) * 2 * .pi)
            if hop > 0.5 {
                frame.lift = -3
                frame.leftLegLift = 1
                frame.rightLegLift = 1
            } else if hop > 0 {
                frame.lift = -1
            } else if hop < -0.6 {
                // 着地。
                frame.crouch = 1
            }
        }
    }

    private static func clampedPhase(_ phase: Double) -> Double {
        guard phase.isFinite else { return 0 }
        return min(1, max(0, phase))
    }
}
