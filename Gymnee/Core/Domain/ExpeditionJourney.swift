import Foundation

/// 遠征の「道中」。送って待って受け取るだけだと単調なので、帰還時に何が起きたかを見せる。
///
/// 出来事は遠征 id をシードにした決定的生成で、報酬と同じく何度開いても同じ物語になる。
/// 出来事によって強さが変わることはない（変えると現実以外で強くなってしまう）。
enum ExpeditionJourney {

    struct Event: Identifiable, Equatable, Sendable {
        /// 表示順（0 始まり）。同じ遠征内で一意。
        let id: Int
        let text: String
        let symbol: String
        /// 良い出来事か（表示色の出し分け用）。
        let isGood: Bool
    }

    /// 出来事の候補。コースの雰囲気に寄せて選ぶ。
    private struct Beat: Sendable {
        let text: String
        let symbol: String
        let isGood: Bool
    }

    private static let common: [Beat] = [
        Beat(text: "道でランナーとすれ違い、軽く会釈した", symbol: "figure.run", isGood: true),
        Beat(text: "水分補給を忘れて少しバテた", symbol: "drop.fill", isGood: false),
        Beat(text: "良い眺めの場所で一息ついた", symbol: "sun.max.fill", isGood: true),
        Beat(text: "近道を選んだら遠回りだった", symbol: "arrow.triangle.turn.up.right.diamond.fill", isGood: false),
        Beat(text: "野良猫がしばらくついてきた", symbol: "pawprint.fill", isGood: true),
        Beat(text: "急な雨に降られて雨宿りした", symbol: "cloud.rain.fill", isGood: false),
        Beat(text: "落ちていた古いプレートを拾った", symbol: "scalemass.fill", isGood: true),
        Beat(text: "階段を全部登りきった", symbol: "figure.stairs", isGood: true),
    ]

    private static let byCourse: [String: [Beat]] = [
        "morning-hill": [
            Beat(text: "朝焼けが背中を押した", symbol: "sunrise.fill", isGood: true),
            Beat(text: "寝起きの体が思うように動かなかった", symbol: "zzz", isGood: false),
        ],
        "iron-forest": [
            Beat(text: "森の奥で重い岩を押し返した", symbol: "mountain.2.fill", isGood: true),
            Beat(text: "枝に足を取られて転びかけた", symbol: "leaf.fill", isGood: false),
            Beat(text: "手強い相手と鉢合わせ、なんとか振り切った", symbol: "flame.fill", isGood: true),
        ],
        "old-gym": [
            Beat(text: "埃をかぶったダンベルを磨いた", symbol: "sparkles", isGood: true),
            Beat(text: "床が抜けそうな場所を慎重に進んだ", symbol: "exclamationmark.triangle.fill", isGood: false),
            Beat(text: "壁に残る昔のトレーニング記録を読んだ", symbol: "book.fill", isGood: true),
        ],
        "summit": [
            Beat(text: "森林限界を越え、風が強くなった", symbol: "wind", isGood: false),
            Beat(text: "夜営して星を眺めた", symbol: "moon.stars.fill", isGood: true),
            Beat(text: "頂上に立ち、来た道を見下ろした", symbol: "flag.fill", isGood: true),
        ],
    ]

    private static let coopBeats: [Beat] = [
        Beat(text: "仲間と背中を預け合って進んだ", symbol: "person.2.fill", isGood: true),
        Beat(text: "分かれ道で仲間の勘に従って正解だった", symbol: "arrow.triangle.branch", isGood: true),
        Beat(text: "仲間が見つけた抜け道で時間を稼いだ", symbol: "figure.walk.motion", isGood: true),
    ]

    /// 道中の出来事（3〜4 件）。`coop` が true なら仲間との出来事が必ず 1 件混ざる。
    static func events(courseId: String, seed: UUID, coop: Bool = false) -> [Event] {
        var pool = common + (byCourse[courseId] ?? [])
        var rng = SplitMix64(seed: seedValue(seed) ^ 0x4A55_524E_4559_0001)
        let count = 3 + Int(rng.next() % 2)

        var picked: [Beat] = []
        if coop, !coopBeats.isEmpty {
            picked.append(coopBeats[Int(rng.next() % UInt64(coopBeats.count))])
        }
        while picked.count < count, !pool.isEmpty {
            let index = Int(rng.next() % UInt64(pool.count))
            picked.append(pool.remove(at: index))
        }
        return picked.enumerated().map { Event(id: $0.offset, text: $0.element.text, symbol: $0.element.symbol, isGood: $0.element.isGood) }
    }

    /// UUID → 64bit シード（FNV-1a）。`Expedition` と同じ方式だが、出来事と報酬で系列を変えるため別にする。
    private static func seedValue(_ uuid: UUID) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: uuid.uuid) { raw in
            for byte in raw {
                value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            }
        }
        return value
    }

    private struct SplitMix64 {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
