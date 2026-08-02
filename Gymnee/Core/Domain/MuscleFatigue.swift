import Foundation

/// 部位ごとの疲労度（人体図の塗り分け）。純粋ロジックでユニットテスト対象。
///
/// `RecoveryAnalyzer` は「最後に鍛えてからの経過時間」だけを見るため、1 セットだけ触った部位も
/// 追い込んだ部位も同じ濃さになってしまう。ここでは **どれだけやったか（負荷量）× どれだけ休んだか**
/// を掛け合わせて 0…1 の疲労度にする。
///
/// - 負荷量: 直近セッションのその部位のセット数を `heavySetCount` で正規化（多いほど 1 に近づく）
/// - 回復:   `RecoveryAnalyzer.recoveryProgress`（部位ごとの推奨回復時間に対する経過割合）
///
/// `RecoveryAnalyzer` 自体は AI 週次計画から使われているので壊さず、この型を上に薄く重ねている。
enum MuscleFatigue {

    /// 疲労度が満点になるセット数。これ以上やっても濃さは変わらない（見た目の飽和を防ぐ）。
    static let heavySetCount = 12

    /// 1 部位分の疲労度。
    struct Status: Equatable, Identifiable {
        let muscle: MuscleGroup
        /// 最後に鍛えた日時（未訓練は nil）。
        let lastTrained: Date?
        /// 直近セッションのセット数。
        let lastSetCount: Int
        /// 0.0（回復済み・未訓練）〜 1.0（直後に高ボリューム）。
        let fatigue: Double
        var id: String { muscle.rawValue }

        /// 表示の3段階。凡例と色分けの境目を 1 箇所に集約する。
        var level: Level { MuscleFatigue.level(for: fatigue) }
    }

    /// 疲労度 → 表示の3段階。人体図の縁取りなど `Status` を持たない側からも使う。
    static func level(for fatigue: Double) -> Level {
        guard fatigue.isFinite else { return .recovered }
        if fatigue < 0.15 { return .recovered }
        if fatigue < 0.55 { return .recovering }
        return .fatigued
    }

    enum Level: String, CaseIterable, Sendable {
        case recovered, recovering, fatigued

        var label: String {
            switch self {
            case .recovered: return "回復済み"
            case .recovering: return "回復中"
            case .fatigued: return "疲労"
            }
        }
    }

    /// 集計の入力（SwiftData 非依存の値型）。View 側で完了ワークアウトから組み立てる。
    struct SessionEntry: Equatable, Sendable {
        let muscle: MuscleGroup
        /// そのセッションの完了時刻（`completedAt` に一本化する。`date` とズレる後追い記録があるため）。
        let completedAt: Date
        /// そのセッション・その部位のセット数。
        let setCount: Int

        init(muscle: MuscleGroup, completedAt: Date, setCount: Int) {
            self.muscle = muscle
            self.completedAt = completedAt
            self.setCount = setCount
        }
    }

    /// 全対象部位の疲労度（`RecoveryAnalyzer.trackedMuscles` の順）。
    /// 同じ部位に複数セッションがあれば**最新のもの**だけを見る（古い疲労は回復で消えている前提）。
    static func statuses(entries: [SessionEntry], asOf reference: Date = .now) -> [Status] {
        var latest: [MuscleGroup: SessionEntry] = [:]
        for e in entries {
            // 未来日の記録（時刻ズレ・手入力ミス）は基準時刻より後なので無視する。
            guard e.completedAt <= reference else { continue }
            if let current = latest[e.muscle], current.completedAt >= e.completedAt { continue }
            latest[e.muscle] = e
        }

        return RecoveryAnalyzer.trackedMuscles.map { muscle in
            guard let entry = latest[muscle] else {
                return Status(muscle: muscle, lastTrained: nil, lastSetCount: 0, fatigue: 0)
            }
            let hours = max(0, reference.timeIntervalSince(entry.completedAt) / 3600.0)
            let recoveryHours = RecoveryAnalyzer.recoveryHours(for: muscle)
            let recoveryProgress = recoveryHours > 0 ? min(hours / recoveryHours, 1.0) : 1.0
            let intensity = intensityFactor(setCount: entry.setCount)
            let fatigue = (intensity * (1.0 - recoveryProgress)).clampedToUnitInterval
            return Status(muscle: muscle, lastTrained: entry.completedAt, lastSetCount: entry.setCount, fatigue: fatigue)
        }
    }

    /// セット数 → 負荷係数（0…1）。0 セットは 0、`heavySetCount` 以上で 1。
    static func intensityFactor(setCount: Int) -> Double {
        guard setCount > 0, heavySetCount > 0 else { return 0 }
        return min(Double(setCount) / Double(heavySetCount), 1.0)
    }

    /// 次にやる候補（疲労が低い順。同点なら大筋群を先に）。
    /// 大筋群も同点なら `trackedMuscles` の並び順で決める ―― `sorted` は同値の順序を保証しないため、
    /// これが無いと再描画のたびに「次は◯◯が狙い目」の提案がちらつく。
    static func recommendedNext(from statuses: [Status]) -> [MuscleGroup] {
        let order = Dictionary(uniqueKeysWithValues: RecoveryAnalyzer.trackedMuscles.enumerated().map { ($1, $0) })
        return statuses
            .filter { $0.level == .recovered }
            .sorted { lhs, rhs in
                if lhs.fatigue != rhs.fatigue { return lhs.fatigue < rhs.fatigue }
                let lh = RecoveryAnalyzer.recoveryHours(for: lhs.muscle)
                let rh = RecoveryAnalyzer.recoveryHours(for: rhs.muscle)
                if lh != rh { return lh > rh }
                return (order[lhs.muscle] ?? .max) < (order[rhs.muscle] ?? .max)
            }
            .map(\.muscle)
    }
}

private extension Double {
    /// NaN / 無限大が混ざっても 0…1 に落とす（Int 変換や描画でトラップしないように）。
    var clampedToUnitInterval: Double {
        guard isFinite else { return 0 }
        return Swift.min(Swift.max(self, 0), 1)
    }
}
