import Foundation

/// 1 人用の冒険マップ（issue #155）。
///
/// 週ボスはパーティの遊びで、本番のパーティは 1 人のものが多い。1 人でも「先に目的地が見える」遊びとして、
/// **完了したワークアウト 1 回 ＝ マップを 1 マス**進む道を置く。数マスごとに中ボス、地方の最後に大ボスがいて、
/// 地方を抜けると次の地方へ進む。最後の地方を抜けたら 2 周目に入る。
///
/// 進みは完了した回数だけで決まる（保存しない・重さやセット数は関係ない）。
/// 「詰め込むより通う回数を評価する」という育成の考え方に合わせ、1 日に何回記録しても 1 回は 1 マス。
enum AdventureMap {

    struct Region: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        /// この地方のマス数（最後のマスが大ボス）。
        let steps: Int
        /// 大ボス（週ボスの絵の強いランク）。
        let bossId: String
    }

    /// 地方。名前は遠征のコースと同じ（`Expedition.courses`）。
    static let regions: [Region] = [
        Region(id: "morning-hill", name: "朝の丘", steps: 10, bossId: "sloth_slime"),
        Region(id: "iron-forest", name: "鉄の森", steps: 15, bossId: "couch_golem"),
        Region(id: "old-gym", name: "廃ジム", steps: 20, bossId: "junk_kraken"),
        Region(id: "summit", name: "頂", steps: 25, bossId: "snooze_dragon"),
    ]

    /// 1 周のマス数。
    static var stepsPerLap: Int { regions.reduce(0) { $0 + $1.steps } }

    /// 中ボスが出る間隔（地方の中で 5 マスごと。最後のマスは大ボスなので除く）。
    static let midBossEvery = 5

    // MARK: - 位置

    struct Position: Equatable, Sendable {
        /// 何周目か（1 始まり）。
        let lap: Int
        let regionIndex: Int
        /// いまの地方で進んだマス数（0...steps-1。地方を抜けた瞬間に次の地方の 0 になる）。
        let step: Int
        /// これまでに進んだマスの合計。
        let totalSteps: Int

        var region: Region { AdventureMap.regions[regionIndex] }
    }

    /// 完了したワークアウトの回数から、いまの位置を求める。
    static func position(completedWorkouts: Int) -> Position {
        let total = max(0, completedWorkouts)
        let lap = total / stepsPerLap
        var rest = total % stepsPerLap
        for (index, region) in regions.enumerated() {
            if rest < region.steps {
                return Position(lap: lap + 1, regionIndex: index, step: rest, totalSteps: total)
            }
            rest -= region.steps
        }
        return Position(lap: lap + 1, regionIndex: 0, step: 0, totalSteps: total)
    }

    // MARK: - マス

    enum Node: Equatable, Sendable {
        case path
        case midBoss(bossId: String)
        case regionBoss(bossId: String)
    }

    /// 地方の n マス目（1 始まり）に何がいるか。最後のマスは大ボス、5 マスごとに中ボス。
    /// 中ボスは週ボスの顔ぶれを順に回す（弱いランクの絵で出す）。
    static func node(regionIndex: Int, step: Int) -> Node {
        guard regions.indices.contains(regionIndex) else { return .path }
        let region = regions[regionIndex]
        if step == region.steps { return .regionBoss(bossId: region.bossId) }
        guard step > 0, step % midBossEvery == 0 else { return .path }
        let order = PartyBoss.catalog.map(\.id)
        let index = (regionIndex + step / midBossEvery) % order.count
        return .midBoss(bossId: order[index])
    }

    /// 次の山場（中ボスか大ボス）と、そこまでの残り回数。
    static func nextEncounter(from position: Position) -> (node: Node, remaining: Int) {
        let region = position.region
        var step = position.step + 1
        while step <= region.steps {
            let n = node(regionIndex: position.regionIndex, step: step)
            if n != .path { return (n, step - position.step) }
            step += 1
        }
        return (.regionBoss(bossId: region.bossId), region.steps - position.step)
    }

    /// 抜けた地方の数（周回を含めた合計）。称号の判定に使う。
    static func clearedRegions(completedWorkouts: Int) -> Int {
        let total = max(0, completedWorkouts)
        var cleared = (total / stepsPerLap) * regions.count
        var rest = total % stepsPerLap
        for region in regions {
            guard rest >= region.steps else { break }
            cleared += 1
            rest -= region.steps
        }
        return cleared
    }

    // MARK: - 1 回で起きたこと

    /// 1 回の記録でマップに起きたこと（完了直後の祝いに使う）。
    enum Event: Equatable, Sendable {
        /// 中ボスを倒した。
        case defeatedMidBoss(bossId: String)
        /// 大ボスを倒して地方を抜けた（次の地方の名前）。
        case clearedRegion(region: String, next: String)
        /// ただ進んだ。
        case advanced
    }

    /// 完了回数が `before` → `before + 1` になったときの出来事。
    static func event(completedBefore before: Int) -> Event {
        let from = position(completedWorkouts: before)
        let reached = from.step + 1
        switch node(regionIndex: from.regionIndex, step: reached) {
        case .regionBoss:
            let next = position(completedWorkouts: before + 1)
            return .clearedRegion(region: from.region.name, next: next.region.name)
        case .midBoss(let bossId):
            return .defeatedMidBoss(bossId: bossId)
        case .path:
            return .advanced
        }
    }
}
