import Foundation

/// 称号（issue #155）。
///
/// 実績（`AchievementCalculator`）はプロフィールに静かに並べるだけだったが、称号は**人に見せる**ためのもの。
/// 行動から称号がつき、選んだ 1 つがフィードの投稿と週ボスのパーティで名前の横に出る。
///
/// 判定はすべて完了した記録などの事実から導出する（保存するのは「どれを着けているか」だけ）。
/// 強さには効かない。
enum PlayerTitle {

    struct Title: Identifiable, Equatable, Sendable {
        /// 送信・保存に使う不変の id（名前を変えても id は変えない）。
        let id: String
        let name: String
        /// 取り方（図鑑に出す）。
        let howTo: String
        /// どこまで進んだかを数える物差しと、その目標。
        let metric: Metric
        let target: Int
    }

    /// 称号の判定に使う数え方。
    enum Metric: Equatable, Sendable {
        case workouts
        /// 朝（4〜7 時台に始めた）のワークアウト。
        case earlyWorkouts
        /// 夜（21 時以降に始めた）のワークアウト。
        case lateWorkouts
        /// その部位を含むワークアウト（部位はいくつかまとめて数える）。
        case workoutsWith([MuscleGroup])
        case personalRecords
        case longestWeeklyStreak
        case learnedTechniques
        case clearedRegions
        case bossDefeats
        case seasonalDefeat(SeasonalEvent)
    }

    /// 称号の一覧。並びは図鑑の順。
    static let catalog: [Title] = [
        Title(id: "first-step", name: "はじめの一歩", howTo: "ワークアウトを 1 回記録する", metric: .workouts, target: 1),
        Title(id: "regular", name: "ジムの常連", howTo: "ワークアウトを 30 回記録する", metric: .workouts, target: 30),
        Title(id: "veteran", name: "百戦錬磨", howTo: "ワークアウトを 100 回記録する", metric: .workouts, target: 100),
        Title(id: "dawn", name: "夜明けの戦士", howTo: "朝 4〜7 時台に 10 回はじめる", metric: .earlyWorkouts, target: 10),
        Title(id: "night", name: "真夜中の求道者", howTo: "夜 21 時以降に 10 回はじめる", metric: .lateWorkouts, target: 10),
        Title(id: "chest", name: "胸板の騎士", howTo: "胸の種目を 20 回の記録でやる", metric: .workoutsWith([.chest]), target: 20),
        Title(id: "back", name: "背中で語る者", howTo: "背中の種目を 20 回の記録でやる", metric: .workoutsWith([.back]), target: 20),
        Title(id: "legs", name: "脚の鬼", howTo: "脚・臀部の種目を 20 回の記録でやる", metric: .workoutsWith([.legs, .glutes]), target: 20),
        Title(id: "shoulders", name: "肩メロン職人", howTo: "肩の種目を 20 回の記録でやる", metric: .workoutsWith([.shoulders]), target: 20),
        Title(id: "arms", name: "腕っぷし自慢", howTo: "二頭・三頭の種目を 20 回の記録でやる", metric: .workoutsWith([.arms]), target: 20),
        Title(id: "core", name: "鉄壁の体幹", howTo: "腹・体幹の種目を 20 回の記録でやる", metric: .workoutsWith([.abs, .core]), target: 20),
        Title(id: "pr-hunter", name: "自己ベストハンター", howTo: "自己ベストを 10 回更新する", metric: .personalRecords, target: 10),
        Title(id: "streak", name: "皆勤の勇者", howTo: "週の目標を 8 週続けて達成する", metric: .longestWeeklyStreak, target: 8),
        Title(id: "technique", name: "技のコレクター", howTo: "技を 20 個覚える", metric: .learnedTechniques, target: 20),
        Title(id: "explorer", name: "冒険者", howTo: "冒険マップの地方を 1 つ抜ける", metric: .clearedRegions, target: 1),
        Title(id: "conqueror", name: "頂を越えし者", howTo: "冒険マップを 1 周する", metric: .clearedRegions, target: AdventureMap.regions.count),
        Title(id: "slayer", name: "ボススレイヤー", howTo: "週ボスを 5 回倒す", metric: .bossDefeats, target: 5),
        Title(id: "halloween", name: "カボチャ退治", howTo: "ハロウィンの週ボスを倒す", metric: .seasonalDefeat(.halloween), target: 1),
        Title(id: "christmas", name: "聖夜の勇者", howTo: "クリスマスの週ボスを倒す", metric: .seasonalDefeat(.christmas), target: 1),
        Title(id: "new-year", name: "初トレの達人", howTo: "お正月の週ボスを倒す", metric: .seasonalDefeat(.newYear), target: 1),
    ]

    /// 着けている称号の保存キー（端末ごと。送るときは見た目と投稿に id を載せる）。
    static let selectedKey = "gymnee.title.selected"

    static func title(id: String?) -> Title? {
        guard let id else { return nil }
        return catalog.first { $0.id == id }
    }

    // MARK: - 判定

    /// 判定に使う事実。呼び出し側が完了した記録・報酬・図鑑から用意する。
    struct Stats: Equatable, Sendable {
        var workouts = 0
        var earlyWorkouts = 0
        var lateWorkouts = 0
        /// 部位 → その部位を含んだワークアウトの回数。
        var workoutsByMuscle: [MuscleGroup: Int] = [:]
        var personalRecords = 0
        var longestWeeklyStreak = 0
        var learnedTechniques = 0
        var clearedRegions = 0
        var bossDefeats = 0
        var seasonalDefeats: Set<SeasonalEvent> = []
    }

    /// その称号の物差しで数えた今の値。
    static func value(of title: Title, stats: Stats) -> Int {
        switch title.metric {
        case .workouts: return stats.workouts
        case .earlyWorkouts: return stats.earlyWorkouts
        case .lateWorkouts: return stats.lateWorkouts
        // まとめた部位は「どれかを含む回」ではなく部位ごとの回数の多いほうで数える（同じ回を二重に数えない）。
        case .workoutsWith(let muscles): return muscles.map { stats.workoutsByMuscle[$0] ?? 0 }.max() ?? 0
        case .personalRecords: return stats.personalRecords
        case .longestWeeklyStreak: return stats.longestWeeklyStreak
        case .learnedTechniques: return stats.learnedTechniques
        case .clearedRegions: return stats.clearedRegions
        case .bossDefeats: return stats.bossDefeats
        case .seasonalDefeat(let event): return stats.seasonalDefeats.contains(event) ? 1 : 0
        }
    }

    static func isEarned(_ title: Title, stats: Stats) -> Bool {
        value(of: title, stats: stats) >= title.target
    }

    /// 手に入れた称号（図鑑の順）。
    static func earned(stats: Stats) -> [Title] {
        catalog.filter { isEarned($0, stats: stats) }
    }

    /// 着けている称号。選んだものを持っていなければ（データが壊れた・条件の数え方が変わった）何も着けない。
    static func resolve(selectedId: String?, stats: Stats) -> Title? {
        guard let title = title(id: selectedId), isEarned(title, stats: stats) else { return nil }
        return title
    }

    /// 「朝」と「夜」の区切り。始めた時刻（端末の暦）の時で判定する。
    static func isEarly(hour: Int) -> Bool { (4..<8).contains(hour) }
    static func isLate(hour: Int) -> Bool { hour >= 21 }

    // MARK: - 他人に見せる名前

    /// 称号の文字数の上限（他人が書いた値を描くので丸める）。
    static let maxDisplayLength = 12

    /// 他人の見た目・投稿に入っていた称号の id を、画面に出す名前にする。知らない id は出さない
    /// （新しいアプリで増えた称号を古いアプリが受け取っても、空欄になるだけで壊れない）。
    static func displayName(forId id: String?) -> String? {
        title(id: id).map { String($0.name.prefix(maxDisplayLength)) }
    }
}
