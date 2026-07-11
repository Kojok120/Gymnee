import Foundation

/// 記録ページ先頭の「よくやる種目」ランキング（§記録リデザイン拡張・2026-07-11 ユーザー確定仕様）。
///
/// 基準: 直近 60 日の**完了ワークアウトでの登場回数**が多い順にトップ 10。
/// 同数なら最終使用日が新しい順。対象種目が 3 未満ならセクション自体を出さない
/// （新規ユーザーに空枠を見せない）。
enum FrequentExerciseRanker {
    /// - Parameters:
    ///   - usage: 種目 id → その種目を含む完了ワークアウトの日付リスト
    ///   - asOf: 基準日（テスト容易性のため注入）
    /// - Returns: 表示順の種目 id（対象が minExercises 未満なら空＝セクション非表示）
    static func rank(
        usage: [UUID: [Date]],
        asOf: Date,
        windowDays: Int = 60,
        limit: Int = 10,
        minExercises: Int = 3
    ) -> [UUID] {
        let cutoff = asOf.addingTimeInterval(-TimeInterval(windowDays) * 86_400)
        // 期間内の使用回数と最終使用日を集計（期間外のみの種目は対象外）。
        let scored: [(id: UUID, count: Int, lastUsed: Date)] = usage.compactMap { id, dates in
            let inWindow = dates.filter { $0 >= cutoff && $0 <= asOf }
            guard let last = inWindow.max() else { return nil }
            return (id, inWindow.count, last)
        }
        guard scored.count >= minExercises else { return [] }
        return scored
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                if $0.lastUsed != $1.lastUsed { return $0.lastUsed > $1.lastUsed }
                return $0.id.uuidString < $1.id.uuidString   // 安定順（テスト・描画のブレ防止）
            }
            .prefix(limit)
            .map(\.id)
    }
}
