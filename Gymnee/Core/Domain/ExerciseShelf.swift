import Foundation

/// 記録画面カテゴリタブの「表示セット（シェルフ）」ロジック（記録リデザイン v2）。
/// 各部位タブに出す種目カードの既定（頻度優先→定番補完）と、ユーザーカスタマイズの
/// 永続構造を持つ。純粋ロジックでユニットテスト対象。
enum ExerciseShelf {
    /// 部位ごとの定番プリセット種目名（履歴不足時の補完用）。
    /// id ではなく名前キーで持つ：プリセットの同名別id増殖・再seedに影響されない。
    /// 全名称が SeedData.presetExercises に存在すること（テストで網羅チェック）。
    static let standardNames: [MuscleGroup: [String]] = [
        .chest: ["ベンチプレス", "ダンベルプレス", "チェストプレス"],
        .back: ["ラットプルダウン", "デッドリフト", "シーテッドロウ"],
        .shoulders: ["ショルダープレス", "サイドレイズ", "ダンベルショルダープレス"],
        .arms: ["ダンベルカール", "バーベルカール", "トライセプスプレスダウン"],
        .abs: ["クランチ", "レッグレイズ", "アブローラー"],
        .core: ["プランク"],
        .glutes: ["ヒップスラスト"],
        .legs: ["スクワット", "レッグプレス", "レッグエクステンション"],
        .cardio: ["ランニング", "ウォーキング", "バイシクル"],
        .fullBody: ["バーピー", "ケトルベルスイング", "クリーン&ジャーク"],
        .other: [],
    ]

    /// 未カスタマイズ時の既定表示。頻度上位を優先し、不足分を定番で補完する（重複除外・順序保持）。
    /// 候補が limit に満たない場合はあるだけ返す（空タブは「その他」カードのみになる）。
    static func defaultIds(frequencyRanked: [UUID], standards: [UUID], limit: Int = 3) -> [UUID] {
        var result: [UUID] = []
        for id in frequencyRanked + standards where !result.contains(id) {
            result.append(id)
            if result.count == limit { break }
        }
        return result
    }

    /// 保存済みシェルフの解決。削除済み種目の id を除外する（順序維持・保存値は書き換えない）。
    static func resolve(stored: [UUID], existing: Set<UUID>) -> [UUID] {
        stored.filter { existing.contains($0) }
    }
}

/// タブごとのカスタム表示セット。@AppStorage("gymnee.recordShelves") に JSON 文字列で保存する。
/// キー無し＝未カスタマイズ（既定表示）、空配列＝「全部外した」として区別する。
struct ExerciseShelves: Codable, Equatable {
    /// MuscleGroup.rawValue → 表示する種目 id（表示順）。
    var byGroup: [String: [UUID]] = [:]

    /// この部位のカスタムシェルフ（nil＝未カスタマイズ＝既定表示）。
    func shelf(for group: MuscleGroup) -> [UUID]? { byGroup[group.rawValue] }

    /// 種目を追加する。未カスタマイズなら現在の表示リスト（既定）を実体化してから適用する
    /// （以後、既定の頻度変動に左右されない＝ユーザーが置いた並びを保つ）。
    mutating func add(_ id: UUID, to group: MuscleGroup, current: [UUID]) {
        var list = byGroup[group.rawValue] ?? current
        if !list.contains(id) { list.append(id) }
        byGroup[group.rawValue] = list
    }

    /// 種目をタブから外す。未カスタマイズなら現在の表示リストを実体化してから適用する。
    mutating func remove(_ id: UUID, from group: MuscleGroup, current: [UUID]) {
        var list = byGroup[group.rawValue] ?? current
        list.removeAll { $0 == id }
        byGroup[group.rawValue] = list
    }

    /// JSON 文字列から復元。破損・空文字は空シェルフ（＝全タブ既定表示）に fail-safe。
    static func decode(from json: String) -> ExerciseShelves {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ExerciseShelves.self, from: data) else {
            return ExerciseShelves()
        }
        return decoded
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
