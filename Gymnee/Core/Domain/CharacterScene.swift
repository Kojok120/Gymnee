import CoreGraphics
import Foundation

/// 育成タブのシーン演出（純粋関数）。
///
/// キャラを「画面の中で生きているもの」に見せるための姿勢を、**時刻から決定的に**導出する。
/// 状態を保存しないので、タブを切り替えても・アプリを落として開き直しても破綻せず、
/// 同じ時刻・同じシードなら常に同じ姿勢になる（＝テストできる）。
///
/// この層は**描画方式に依存しない**。ベクターで描こうと部位分割した画像を貼ろうと、
/// 「どこに立ち、どちらを向き、どの関節を何度回すか」は同じ。
/// 絵を差し替えるときに書き換えるのは描画側だけで、ここは触らない。
enum CharacterScene {

    // MARK: - 行動

    /// 歩いていない間に挟む仕草。ジムの生活感が出るものだけに絞る。
    enum Emote: String, CaseIterable, Sendable {
        /// ぼーっと立つ（一番よく出る）。
        case rest
        /// スクワット。
        case squat
        /// 伸びをする。
        case stretch
        /// ダンベルカール。
        case curl
        /// ガッツポーズで跳ねる。
        case cheer

        /// 抽選の重み。何もしていない時間を長めに取り、たまに動く方が生き物らしい。
        var weight: Int {
            switch self {
            case .rest: return 40
            case .squat: return 15
            case .stretch: return 18
            case .curl: return 15
            case .cheer: return 12
            }
        }

        /// 仕草の反復回数（`emotePhase` をこの回数だけ繰り返す）。
        var repeats: Int {
            switch self {
            case .rest: return 1
            case .squat: return 3
            case .stretch: return 1
            case .curl: return 4
            case .cheer: return 2
            }
        }
    }

    enum Behavior: Equatable, Sendable {
        case walking
        case emoting(Emote)
    }

    /// ある時刻のキャラの姿勢。描画側はこれをそのまま絵にする。
    struct Pose: Equatable, Sendable {
        /// 立ち位置。x/y とも 0...1 の正規化値（y は 0＝奥 / 1＝手前）。実寸への変換は描画側。
        var position: CGPoint
        /// 右を向いているか。
        var facingRight: Bool
        var behavior: Behavior
        /// 歩行サイクルの位相（0...1）。手足のスイングに使う。
        var walkPhase: Double
        /// 仕草の進行（0...1、反復込み）。
        var emotePhase: Double
        /// 呼吸の上下（-1...1）。
        var breathPhase: Double
        /// まぶたの閉じ具合（0＝開いている / 1＝閉じている）。
        var blink: Double
    }

    // MARK: - 徘徊のパラメータ

    /// 1 区間の長さ（秒）。前半で次の目的地へ歩き、後半はその場で仕草をする。
    static let segmentDuration: TimeInterval = 8.0
    /// 区間のうち歩きに使う割合。
    static let walkFraction: Double = 0.42
    /// 歩行サイクルの速さ（1 秒あたりの歩数）。
    static let stepsPerSecond: Double = 1.7
    /// 呼吸 1 周期の秒数。
    static let breathPeriod: TimeInterval = 3.4

    /// 歩き回れる範囲（正規化）。端に寄りすぎて見切れないように内側へ寄せる。
    static let xRange: ClosedRange<Double> = 0.10...0.90
    static let yRange: ClosedRange<Double> = 0.12...0.92

    /// この距離未満しか移動しない区間は「歩いた」ことにせず、その場の仕草として扱う。
    /// 数ピクセルの移動で歩行アニメが出ると、足踏みしているように見えて不自然なため。
    static let minimumWalkDistance: Double = 0.04

    // MARK: - 姿勢の導出

    /// 指定時刻の姿勢。`seed` を変えると別人の歩き方になる（仲間キャラ用）。
    ///
    /// 区間 i の間は `waypoint(i)` から `waypoint(i+1)` へ移動し、着いたら次の区間まで仕草をする。
    /// 位置を「区間の端点の補間」で表すので、経過時間がいくら大きくても O(1) で求まり、
    /// 区間の境目でも位置が飛ばない（`waypoint(i+1)` が次の区間の始点になるため）。
    static func pose(at time: TimeInterval, seed: UInt64) -> Pose {
        let t = max(0, time)
        let index = Int(min(Double(Int.max / 2), (t / segmentDuration).rounded(.down)))
        let local = t - Double(index) * segmentDuration

        let from = waypoint(seed: seed, index: index)
        let to = waypoint(seed: seed, index: index + 1)
        let travel = distance(from, to)

        let walkTime = segmentDuration * walkFraction
        let emote = emote(seed: seed, index: index)

        // 移動が短すぎる区間は歩かせず、始点に留めてその場の仕草だけにする。
        guard travel >= minimumWalkDistance else {
            return Pose(
                position: from,
                facingRight: facing(seed: seed, index: index),
                behavior: .emoting(emote),
                walkPhase: 0,
                emotePhase: repeatedPhase(min(1, local / segmentDuration), repeats: emote.repeats),
                breathPhase: breath(at: t),
                blink: blink(at: t, seed: seed)
            )
        }

        if local < walkTime {
            let progress = easeInOut(local / walkTime)
            return Pose(
                position: CGPoint(
                    x: from.x + (to.x - from.x) * progress,
                    y: from.y + (to.y - from.y) * progress
                ),
                facingRight: to.x >= from.x,
                behavior: .walking,
                walkPhase: (local * stepsPerSecond).truncatingRemainder(dividingBy: 1),
                emotePhase: 0,
                breathPhase: breath(at: t),
                blink: blink(at: t, seed: seed)
            )
        }

        let rest = segmentDuration - walkTime
        let progress = rest > 0 ? min(1, (local - walkTime) / rest) : 1
        return Pose(
            position: to,
            // 歩き終えた向きのまま仕草に入る（急に振り向かない）。
            facingRight: to.x >= from.x,
            behavior: .emoting(emote),
            walkPhase: 0,
            emotePhase: repeatedPhase(progress, repeats: emote.repeats),
            breathPhase: breath(at: t),
            blink: blink(at: t, seed: seed)
        )
    }

    /// 区間 `index` の目的地。
    static func waypoint(seed: UInt64, index: Int) -> CGPoint {
        var rng = DeterministicRandom(seed: seed &+ 0x9E37_79B9 &* UInt64(bitPattern: Int64(index)))
        return CGPoint(
            x: xRange.lowerBound + rng.unit() * (xRange.upperBound - xRange.lowerBound),
            y: yRange.lowerBound + rng.unit() * (yRange.upperBound - yRange.lowerBound)
        )
    }

    /// 区間 `index` で見せる仕草。
    static func emote(seed: UInt64, index: Int) -> Emote {
        var rng = DeterministicRandom(seed: seed &+ 0xA5A5_5A5A &* UInt64(bitPattern: Int64(index)))
        let all = Emote.allCases
        let total = all.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return .rest }
        var roll = Int(rng.next() % UInt64(total))
        for candidate in all {
            roll -= candidate.weight
            if roll < 0 { return candidate }
        }
        return .rest
    }

    /// 移動しない区間で向いている方向。
    private static func facing(seed: UInt64, index: Int) -> Bool {
        var rng = DeterministicRandom(seed: seed &+ 0x1357_9BDF &* UInt64(bitPattern: Int64(index)))
        return rng.next() % 2 == 0
    }

    /// 呼吸の位相（-1...1）。
    static func breath(at time: TimeInterval) -> Double {
        sin(time / breathPeriod * 2 * .pi)
    }

    // MARK: - まばたき

    /// まばたきの間隔（秒）と、閉じている時間（秒）。
    static let blinkPeriod: TimeInterval = 4.2
    static let blinkDuration: TimeInterval = 0.16

    /// まぶたの閉じ具合（0＝開 / 1＝閉）。周期ごとにランダムな位置で 1 回閉じる。
    static func blink(at time: TimeInterval, seed: UInt64) -> Double {
        let t = max(0, time)
        let slot = (t / blinkPeriod).rounded(.down)
        var rng = DeterministicRandom(seed: seed &+ 0xB16B_00B5 &* UInt64(bitPattern: Int64(slot)))
        let start = rng.unit() * (blinkPeriod - blinkDuration)
        let local = t - slot * blinkPeriod
        guard local >= start, local <= start + blinkDuration else { return 0 }
        let progress = (local - start) / blinkDuration
        return sin(progress * .pi)
    }

    // MARK: - 奥行き

    /// 奥行き（y: 0＝奥 / 1＝手前）に応じた大きさの倍率。手前ほど大きく見せて立体感を出す。
    static func depthScale(_ y: Double) -> Double {
        let clamped = min(1, max(0, y.isFinite ? y : 0))
        return 0.80 + 0.28 * clamped
    }

    // MARK: - 時間帯

    /// 窓の外の時間帯。開くたびに部屋の光が違う＝「今」を映している感を出す。
    enum TimeOfDay: String, CaseIterable, Sendable {
        case dawn, day, dusk, night

        var label: String {
            switch self {
            case .dawn: return "朝"
            case .day: return "昼"
            case .dusk: return "夕"
            case .night: return "夜"
            }
        }
    }

    /// 時刻から時間帯を決める。
    static func timeOfDay(at date: Date, calendar: Calendar = .current) -> TimeOfDay {
        switch calendar.component(.hour, from: date) {
        case 5..<9: return .dawn
        case 9..<16: return .day
        case 16..<19: return .dusk
        default: return .night
        }
    }

    // MARK: - 補助

    /// 区間内の進捗を反復回数ぶん繰り返した位相（0...1）。
    static func repeatedPhase(_ progress: Double, repeats: Int) -> Double {
        let clamped = min(1, max(0, progress.isFinite ? progress : 0))
        guard repeats > 1 else { return clamped }
        return (clamped * Double(repeats)).truncatingRemainder(dividingBy: 1)
    }

    /// 歩き出しと止まりを滑らかにする（等速だとロボットに見える）。
    static func easeInOut(_ x: Double) -> Double {
        let clamped = min(1, max(0, x.isFinite ? x : 0))
        return clamped * clamped * (3 - 2 * clamped)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x)
        let dy = Double(b.y - a.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - 決定的乱数

/// 決定的な擬似乱数（SplitMix64）。同じシードなら常に同じ列を返す。
///
/// `Expedition` にも同等の実装があるが、あちらは**報酬の抽選結果を将来にわたって固定する**責務を持つ。
/// 共通化して片方の都合で挙動を変えると、既存ユーザーの受け取り済み報酬と表示がズレるため、あえて分けている。
struct DeterministicRandom {
    private var state: UInt64

    init(seed: UInt64) {
        // シード 0 でも列が縮退しないように定数を混ぜる。
        state = seed ^ 0x2545_F491_4F6C_DD1D
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0.0（含む）〜 1.0（含まない）の一様乱数。
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}

extension DeterministicRandom {
    /// UUID から安定したシードを作る（FNV-1a）。端末をまたいでも同じ値になる。
    static func seed(from uuid: UUID) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: uuid.uuid) { raw in
            for byte in raw {
                value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            }
        }
        return value
    }
}
