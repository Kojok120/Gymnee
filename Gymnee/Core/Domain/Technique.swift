import Foundation

/// 種目ごとの技と技図鑑（issue #155）。
///
/// 週ボスの技名は系統（上半身など）ごとに 3 つしかなく、どの種目をやっても同じ顔ぶれだった。
/// ここでは**種目そのものを技**にする。初めてやった種目で技を覚え、その種目のセット数で技レベルが上がり、
/// その種目の自己ベストで威力が上がる。プリセットの 96 種目すべてに名前があるので、
/// いつもと違う種目を試す理由になる。
///
/// 値はすべて完了した記録から導出する（保存しない）。「強さは現実でしか上がらない」を崩さないよう、
/// 技は見せ方だけで、EXP・パワー・週ボスのダメージには効かない。
enum Technique {

    // MARK: - 技名

    /// プリセット種目 → 技名。種目名は `SeedData.presetExercises` と同じ文字列（不変）。
    /// 足りないと「秘技・〇〇」に落ちるだけで壊れないが、`TechniqueTests` で 96 件の網羅を確かめている。
    static let presetNames: [String: String] = [
        // 胸
        "ベンチプレス": "鋼鉄プレス",
        "インクラインベンチプレス": "昇竜プレス",
        "デクラインベンチプレス": "落雷プレス",
        "ダンベルプレス": "双鉄プレス",
        "インクラインダンベルプレス": "双竜の昇り",
        "ダンベルフライ": "鷹の翼",
        "ダンベルプルオーバー": "大車輪",
        "チェストプレス": "機甲プレス",
        "インクラインチェストプレス": "機甲プレス・昇",
        "デクラインチェストプレス": "機甲プレス・落",
        "ペックフライ": "蝶の抱擁",
        "ケーブルクロスオーバー": "十字斬り",
        "スミスマシンベンチプレス": "鉄軌道プレス",
        "スミスマシンインクラインベンチプレス": "鉄軌道プレス・昇",
        "腕立て伏せ": "大地押し",
        "ディップス": "沈み撃ち",
        // 背中
        "デッドリフト": "大地引き抜き",
        "ベントオーバーロウ": "鬼引き",
        "ワンハンドロウ": "片手引き斬り",
        "Tバーロウ": "T字引き",
        "ハイロウ": "天引き",
        "ローロウ": "地引き",
        "ラットプルダウン": "翼引き下ろし",
        "シーテッドロウ": "舟漕ぎ斬り",
        "ケーブルプルオーバー": "弧月",
        "バーベルシュラッグ": "肩すくめ衝撃",
        "ダンベルシュラッグ": "双肩すくめ",
        "懸垂": "天昇り",
        "バックエクステンション": "反り返し",
        // 脚
        "スクワット": "大地の踏みこみ",
        "フロントスクワット": "前のめり踏みこみ",
        "スミスマシンスクワット": "鉄軌道踏みこみ",
        "ゴブレットスクワット": "聖杯の構え",
        "ブルガリアンスクワット": "片脚地獄",
        "ランジ": "踏みこみ突き",
        "レッグプレス": "脚甲プレス",
        "ハックスクワット": "斜め踏みこみ",
        "レッグエクステンション": "膝蹴り上げ",
        "レッグカール": "かかと落とし",
        "ルーマニアンデッドリフト": "弓引きの構え",
        "カーフレイズ": "つま先衝撃",
        "ヒップアダクション": "内股締め",
        // 肩
        "ショルダープレス": "天突き",
        "ダンベルショルダープレス": "双天突き",
        "バーベルショルダープレス": "天衝プレス",
        "スミスマシンショルダープレス": "鉄軌道天突き",
        "アーノルドプレス": "旋回天突き",
        "サイドレイズ": "両翼広げ",
        "ケーブルサイドレイズ": "片翼広げ",
        "マシンサイドレイズ": "機甲の翼",
        "フロントレイズ": "前方掲げ",
        "ケーブルフロントレイズ": "光の掲げ",
        "リアレイズ": "背の翼",
        "リアデルトフライ": "後ろ羽ばたき",
        "フェイスプル": "引き寄せの型",
        "アップライトロウ": "直立引き上げ",
        // 二頭・三頭
        "バーベルカール": "剛腕巻き上げ",
        "プリーチャーカール": "説教台の巻き上げ",
        "ダンベルカール": "力こぶ巻き上げ",
        "インクラインダンベルカール": "斜め巻き上げ",
        "コンセントレーションカール": "集中の一撃",
        "ハンマーカール": "鉄槌",
        "マシンアームカール": "機甲巻き上げ",
        "ケーブルカール": "綱巻き",
        "トライセプスプレスダウン": "振り下ろし",
        "スカルクラッシャー": "兜割り",
        "キックバック": "後ろ打ち",
        "オーバーヘッドエクステンション": "頭上の振り下ろし",
        "ナローベンチプレス": "細身プレス",
        // 腹
        "クランチ": "丸まり撃ち",
        "シットアップ": "起き上がり撃ち",
        "レッグレイズ": "脚上げ返し",
        "ハンギングレッグレイズ": "吊り脚上げ",
        "ロシアンツイスト": "旋風ねじり",
        "ケーブルクランチ": "綱の祈り",
        "アブドミナルクランチ": "機甲の丸まり",
        "トーソローテーション": "胴回し",
        "アブローラー": "転がり突撃",
        // 体幹
        "プランク": "鉄壁プランク",
        "サイドプランク": "横の鉄壁",
        // 臀部
        "ヒップスラスト": "腰突き上げ",
        "ヒップアブダクション": "外開きの型",
        "ケーブルキックバック": "後ろ蹴り上げ",
        "ヒップリフト": "橋の構え",
        // 全身
        "バーピー": "跳ね起き連撃",
        "マウンテンクライマー": "山登り連打",
        "ケトルベルスイング": "鐘振り",
        "クリーン&ジャーク": "一気呵成",
        "パワークリーン": "跳ね上げ",
        // 有酸素
        "ウォーキング": "散歩の足音",
        "ランニング": "疾風ダッシュ",
        "バイシクル": "車輪の風",
        "クロストレーナー": "交差の風",
        "ステアクライマー": "天への階段",
        "ローイングマシン": "漕ぎ進め",
        "水泳": "水しぶき",
    ]

    /// 技名。プリセットは専用の名前、自分で作った種目は「秘技・〇〇」。
    static func name(exerciseName: String) -> String {
        presetNames[exerciseName] ?? "秘技・\(exerciseName)"
    }

    // MARK: - 技レベルと威力

    /// 技レベルが上がるセット数（累計）。1 セットで覚えて Lv.1。上限は Lv.10。
    static let levelThresholds = [1, 10, 25, 50, 80, 120, 170, 230, 300, 400]
    static var maxLevel: Int { levelThresholds.count }

    /// 累計セット数 → 技レベル（0 ＝ まだ覚えていない）。
    static func level(sets: Int) -> Int {
        levelThresholds.lastIndex { sets >= $0 }.map { $0 + 1 } ?? 0
    }

    /// 次のレベルまでに要るセット数（上限なら nil）。
    static func setsToNextLevel(sets: Int) -> Int? {
        let current = level(sets: sets)
        guard current < maxLevel else { return nil }
        return levelThresholds[current] - max(0, sets)
    }

    /// 威力。技レベルと、その種目の自己ベストの回数で上がる（見せるだけの数字）。
    static func power(level: Int, prCount: Int) -> Int {
        guard level > 0 else { return 0 }
        return 10 + 6 * (level - 1) + 4 * max(0, prCount)
    }

    // MARK: - 図鑑

    /// 種目ごとの集計（呼び出し側が完了した記録から作る）。
    struct Tally: Equatable, Sendable {
        var exerciseName: String
        var muscle: MuscleGroup
        var completedSets: Int
        var prCount: Int

        init(exerciseName: String, muscle: MuscleGroup, completedSets: Int, prCount: Int = 0) {
            self.exerciseName = exerciseName
            self.muscle = muscle
            self.completedSets = completedSets
            self.prCount = prCount
        }
    }

    /// 図鑑の 1 行。
    struct Entry: Identifiable, Equatable, Sendable {
        var id: String { exerciseName }
        let exerciseName: String
        let techniqueName: String
        let muscle: MuscleGroup
        let level: Int
        let sets: Int
        let power: Int
        /// プリセットにある技か（自作の種目の「秘技」は false）。
        let isPreset: Bool

        var isLearned: Bool { level > 0 }
    }

    /// 図鑑を組み立てる。プリセットの技は覚えていなくても「？？？」として並べ（何で覚えるかは見せる）、
    /// 自作の種目は覚えたものだけ並べる。並びは部位の順 → 覚えたものが先 → レベルの高い順 → 名前。
    static func book(tallies: [Tally], presets: [(name: String, muscle: MuscleGroup)]) -> [Entry] {
        var byName: [String: Tally] = [:]
        for tally in tallies {
            var merged = byName[tally.exerciseName] ?? Tally(exerciseName: tally.exerciseName, muscle: tally.muscle, completedSets: 0)
            merged.completedSets += max(0, tally.completedSets)
            merged.prCount += max(0, tally.prCount)
            byName[tally.exerciseName] = merged
        }
        var entries: [Entry] = []
        var seen: Set<String> = []
        for preset in presets where !seen.contains(preset.name) {
            seen.insert(preset.name)
            entries.append(entry(byName[preset.name] ?? Tally(exerciseName: preset.name, muscle: preset.muscle, completedSets: 0),
                                 muscle: preset.muscle, isPreset: true))
        }
        for tally in byName.values where !seen.contains(tally.exerciseName) && tally.completedSets > 0 {
            entries.append(entry(tally, muscle: tally.muscle, isPreset: presetNames[tally.exerciseName] != nil))
        }
        let order = Dictionary(uniqueKeysWithValues: MuscleGroup.allCases.enumerated().map { ($1, $0) })
        return entries.sorted { lhs, rhs in
            let l = order[lhs.muscle] ?? 0, r = order[rhs.muscle] ?? 0
            if l != r { return l < r }
            if lhs.isLearned != rhs.isLearned { return lhs.isLearned }
            if lhs.level != rhs.level { return lhs.level > rhs.level }
            return lhs.exerciseName < rhs.exerciseName
        }
    }

    private static func entry(_ tally: Tally, muscle: MuscleGroup, isPreset: Bool) -> Entry {
        let level = level(sets: tally.completedSets)
        return Entry(
            exerciseName: tally.exerciseName,
            techniqueName: name(exerciseName: tally.exerciseName),
            muscle: muscle,
            level: level,
            sets: max(0, tally.completedSets),
            power: power(level: level, prCount: tally.prCount),
            isPreset: isPreset
        )
    }

    /// 覚えた技の数。
    static func learnedCount(_ book: [Entry]) -> Int { book.filter(\.isLearned).count }

    // MARK: - 1 セットごとの出来事

    /// 1 セット記録したときに技に起きたこと。記録画面の戦闘で言葉と音を出し分ける。
    enum Event: Equatable, Sendable {
        /// 初めてやった種目（技を覚えた）。
        case learned(name: String)
        /// 技レベルが上がった。
        case leveledUp(name: String, level: Int)
        /// いつもの一撃。
        case used(name: String, level: Int)
    }

    /// その種目の**このセットより前**の累計セット数から、このセットで起きたことを決める。
    static func event(exerciseName: String, setsBefore: Int) -> Event {
        let before = level(sets: setsBefore)
        let after = level(sets: setsBefore + 1)
        let technique = name(exerciseName: exerciseName)
        if before == 0 { return .learned(name: technique) }
        if after > before { return .leveledUp(name: technique, level: after) }
        return .used(name: technique, level: after)
    }
}
