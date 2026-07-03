import Foundation

/// 実績バッジ（静かな実績システム）。通知・ポップアップは出さず、プロフィールに進捗として並べる。
/// しきい値は「継続そのもの」を称える設計（週次ストリークは休息を尊重する既存思想に合わせ、日次は使わない）。
enum AchievementCalculator {
    enum Kind: String, CaseIterable {
        case volume, workouts, prs, visits, weeklyStreak
    }

    /// 種別ごとの実績状況（達成済みラベル列＋次の目標と進捗）。
    struct Status: Equatable, Identifiable {
        let kind: Kind
        let title: String
        let systemImage: String
        /// 達成済みバッジのラベル（小さい順）。空＝未達成。
        let earnedLabels: [String]
        /// 次の目標ラベル（全達成なら nil）。
        let nextLabel: String?
        /// 次の目標への進捗（0...1。全達成なら 1）。
        let progressToNext: Double

        var id: String { kind.rawValue }
    }

    /// しきい値（昇順）。
    static let volumeTiersKg: [Double] = [10_000, 50_000, 100_000, 500_000, 1_000_000]
    static let workoutTiers = [10, 50, 100, 300, 500]
    static let prTiers = [10, 30, 100, 300]
    static let visitTiers = [10, 50, 100, 300, 500]
    static let weeklyStreakTiers = [4, 12, 26, 52]

    /// 現在値から全種別の実績状況を組み立てる。
    static func statuses(
        totalVolumeKg: Double,
        workoutCount: Int,
        prCount: Int,
        visitCount: Int,
        longestWeeklyStreakWeeks: Int
    ) -> [Status] {
        [
            build(kind: .volume, title: "総挙上量", systemImage: "scalemass.fill",
                  value: totalVolumeKg.isFinite ? totalVolumeKg : 0,
                  tiers: volumeTiersKg, label: { "\(Int($0 / 1000))t" }),
            build(kind: .workouts, title: "ワークアウト", systemImage: "dumbbell.fill",
                  value: Double(workoutCount), tiers: workoutTiers.map(Double.init), label: { "\(Int($0))回" }),
            build(kind: .prs, title: "自己ベスト", systemImage: "trophy.fill",
                  value: Double(prCount), tiers: prTiers.map(Double.init), label: { "\(Int($0))" }),
            build(kind: .visits, title: "来店", systemImage: "mappin.and.ellipse",
                  value: Double(visitCount), tiers: visitTiers.map(Double.init), label: { "\(Int($0))回" }),
            build(kind: .weeklyStreak, title: "連続週", systemImage: "flame.fill",
                  value: Double(longestWeeklyStreakWeeks), tiers: weeklyStreakTiers.map(Double.init), label: { "\(Int($0))週" }),
        ]
    }

    private static func build(
        kind: Kind, title: String, systemImage: String,
        value: Double, tiers: [Double], label: (Double) -> String
    ) -> Status {
        let earned = tiers.filter { value >= $0 }
        let next = tiers.first { value < $0 }
        let progress: Double
        if let next {
            let base = earned.last ?? 0
            progress = next > base ? min(1, max(0, (value - base) / (next - base))) : 0
        } else {
            progress = 1
        }
        return Status(
            kind: kind, title: title, systemImage: systemImage,
            earnedLabels: earned.map(label),
            nextLabel: next.map(label),
            progressToNext: progress
        )
    }
}
