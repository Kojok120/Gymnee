import Foundation

/// `PlannedWorkout.detailJSON`（計画の種目内容）の読み書き（issue #121）。
///
/// detailJSON の書き手は3つある:
/// - AI 週計画（plan-workouts → `SupabaseClient.PlanExercise` をそのまま encode。重量キーは `weight`）
/// - コーチ提案（coach-chat。重量キーは `weightKg`）
/// - はじめてのメニュー（`StarterMenu`）
///
/// 読み手（記録画面の計画カード・`PlanStarter`）が `weight` 必須でデコードしていたため、
/// コーチ由来の計画は配列ごとデコードに失敗し、計画タブが空になっていた。
/// 読みはここ1か所に寄せ、`weight` / `weightKg` のどちらでも受ける（端末に残る既存データも救う）。
/// 書きは `weight` に統一する。
enum PlanDetail {
    struct Exercise: Codable, Equatable, Sendable {
        let name: String
        let muscleGroup: String?
        let sets: Int
        let reps: Int
        let weight: Double

        init(name: String, muscleGroup: String?, sets: Int, reps: Int, weight: Double) {
            self.name = name
            self.muscleGroup = muscleGroup
            self.sets = sets
            self.reps = reps
            self.weight = weight
        }

        private enum CodingKeys: String, CodingKey {
            case name, muscleGroup, sets, reps, weight, weightKg
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            muscleGroup = try c.decodeIfPresent(String.self, forKey: .muscleGroup)
            // 外部（LLM）由来の値で記録画面やセット生成が暴れないよう、現実的な範囲に丸める。
            sets = min(max(Self.int(c, .sets) ?? 1, 1), Self.maxSets)
            reps = min(max(Self.int(c, .reps) ?? 1, 1), Self.maxReps)
            weight = min(max(Self.double(c, .weight) ?? Self.double(c, .weightKg) ?? 0, -Self.maxWeight), Self.maxWeight)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(muscleGroup, forKey: .muscleGroup)
            try c.encode(sets, forKey: .sets)
            try c.encode(reps, forKey: .reps)
            try c.encode(weight, forKey: .weight)
        }

        static let maxSets = 20
        static let maxReps = 999
        /// 補助（負の重量）も含め、記録画面が扱う重量の上限。
        static let maxWeight = 500.0

        /// 整数欄は小数で届いても丸めて受ける（LLM 由来の値を想定）。非有限値・巨大値は欠損扱い
        /// （`Int(Double)` のトラップを避ける）。
        private static func int(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
            if let v = try? c.decode(Int.self, forKey: key) { return v }
            if let d = try? c.decode(Double.self, forKey: key), d.isFinite, abs(d) < 1_000_000 {
                return Int(d.rounded())
            }
            return nil
        }

        private static func double(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
            guard let d = try? c.decode(Double.self, forKey: key), d.isFinite else { return nil }
            return d
        }
    }

    /// detailJSON を種目の配列にする。nil・壊れた JSON・名前の無い要素は空として扱う。
    static func decode(_ json: String?) -> [Exercise] {
        guard let json, let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([Exercise].self, from: data)
        else { return [] }
        return items.filter { !$0.name.isEmpty }
    }

    /// 種目の配列を detailJSON にする。空なら nil（計画は「種目なし」のまま）。
    static func encode(_ items: [Exercise]) -> String? {
        guard !items.isEmpty, let data = try? JSONEncoder().encode(items) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
