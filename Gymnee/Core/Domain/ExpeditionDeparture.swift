import CoreGraphics
import Foundation

/// 遠征の出発と留守（純粋関数）。
///
/// 遠征を「シートの中の進行バー」ではなく**部屋の出来事**にする。
/// 送り出すとキャラがグッズを抱えてドアから出ていき、留守中は部屋に置き手紙が残る。
/// 帰還すると宝箱が出る（既存）。キャラの不在そのものが「遠征中」の表示になる。
enum ExpeditionDeparture {

    /// 出発の歩きにかける時間（秒）。
    static let duration: TimeInterval = 2.4

    /// ドアの位置（正規化）。`RoomBackdrop` の描画位置と対で維持する。
    /// x はドアの中心、y はキャラが立つ床の奥行き。
    static let doorSpot = CGPoint(x: 0.88, y: 0.10)

    /// 置き手紙の位置（正規化）。ドアの近くの床。
    static let letterSpot = CGPoint(x: 0.78, y: 0.24)

    // MARK: - 抱えていくグッズ

    /// 出発時に抱えていくグッズ（ドット絵の id）。遠征ごとにランダムで、同じ遠征なら常に同じ。
    static let carriedItemIds = ["dumbbell", "kettlebell", "water-bottle"]

    static func carriedItemId(seed: UUID) -> String {
        var rng = DeterministicRandom(seed: DeterministicRandom.seed(from: seed) &+ 0xCA88)
        return carriedItemIds[Int(rng.next() % UInt64(carriedItemIds.count))]
    }

    // MARK: - 出発の歩き

    /// 出発中の姿勢。今いる場所からドアへ歩く。歩き終えたら nil（＝姿を消す）。
    static func pose(from: CGPoint, elapsed: TimeInterval) -> CharacterScene.Pose? {
        guard elapsed >= 0, elapsed < duration else { return nil }
        let progress = CharacterScene.easeInOut(elapsed / duration)
        let position = CGPoint(
            x: from.x + (doorSpot.x - from.x) * progress,
            y: from.y + (doorSpot.y - from.y) * progress
        )
        return CharacterScene.Pose(
            position: position,
            facing: doorSpot.x >= from.x ? .right : .left,
            behavior: .walking,
            walkPhase: (elapsed * CharacterScene.stepsPerSecond).truncatingRemainder(dividingBy: 1),
            emotePhase: 0,
            breathPhase: CharacterScene.breath(at: elapsed),
            blink: 0
        )
    }

    // MARK: - 置き手紙

    /// 文面のパターン。%1$@＝コース名、%2$@＝残り時間（「あと29分」）。
    /// 開くたびに文面が変わると嘘くさいので、遠征ごとに 1 つを決定的に選ぶ。
    static let letterPatterns = [
        "「%1$@」に行ってきます。%2$@で戻ります。",
        "ちょっと「%1$@」まで。%2$@には帰ります。",
        "「%1$@」でいいものを探してきます。帰りは%2$@。",
        "「%1$@」へ出発。%2$@で戻るので、おみやげを楽しみにしていてください。",
    ]

    static func letterText(courseTitle: String, remaining: String, seed: UUID) -> String {
        var rng = DeterministicRandom(seed: DeterministicRandom.seed(from: seed) &+ 0x1E77E8)
        let pattern = letterPatterns[Int(rng.next() % UInt64(letterPatterns.count))]
        // 「まもなく帰還」をそのまま埋めると「まもなく帰還で戻ります」になり日本語が壊れる。
        let phrase = remaining == "まもなく帰還" ? "まもなく" : remaining
        return String(format: pattern, courseTitle, phrase)
    }
}
