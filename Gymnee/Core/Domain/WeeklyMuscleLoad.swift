import Foundation

/// 今週の部位別トレーニング量（人体図の塗り＝「育ち」）。純粋ロジックでユニットテスト対象。
///
/// 人体図の塗りは元々「疲労度」だった。ところが疲労は休むほど消えるので、
/// 普段の画面＝全身グレー（何も起きていない図）になり、記録した成果がどこにも映らなかった。
/// ここでは **今週その部位を何セットやったか** を週の目安セット数に対する達成度（0…1）に直し、
/// 塗りの主役をそちらへ移す。疲労度（`MuscleFatigue`）は縁取りの補助表示として残す。
///
/// 入力は `MuscleFatigue.SessionEntry` を流用する（部位・完了時刻・セット数と必要な情報が同じで、
/// View 側で 2 種類の配列を組み立てる意味がないため）。
enum WeeklyMuscleLoad {

    /// 週の目安セット数。ここに届くと満タン表示になる。
    /// 肥大の一般的な目安（週 10〜20 セット）の下限側を取り、大筋群ほど多めに置く。
    static func targetSets(for muscle: MuscleGroup) -> Int {
        switch muscle {
        case .chest, .back, .legs: return 12
        case .shoulders, .arms, .glutes: return 10
        case .abs, .core: return 8
        case .cardio, .fullBody, .other: return 10
        }
    }

    /// 1 部位分の今週の量。
    struct Status: Equatable, Identifiable {
        let muscle: MuscleGroup
        /// 今週のセット数（週内の全セッションの合計）。
        let sets: Int
        /// その部位の週の目安セット数。
        let targetSets: Int
        var id: String { muscle.rawValue }

        /// 0.0（今週まだ手つかず）〜 1.0（目安到達）。
        var progress: Double {
            guard sets > 0, targetSets > 0 else { return 0 }
            let value = Double(sets) / Double(targetSets)
            guard value.isFinite else { return 0 }
            return min(value, 1.0)
        }

        /// 今週まだ 1 セットもやっていない。
        var isUntouched: Bool { sets == 0 }
        /// 目安に到達している。
        var isComplete: Bool { targetSets > 0 && sets >= targetSets }
    }

    /// 全対象部位の今週の量（`RecoveryAnalyzer.trackedMuscles` の順）。
    /// 疲労度と違い、**週内の全セッションを合算**する（週の積み上げを見せるため）。
    static func statuses(
        entries: [MuscleFatigue.SessionEntry],
        asOf reference: Date = .now,
        calendar: Calendar = .current
    ) -> [Status] {
        var setsByMuscle: [MuscleGroup: Int] = [:]
        if let week = calendar.dateInterval(of: .weekOfYear, for: reference) {
            for e in entries {
                // 未来日の記録（時刻ズレ・手入力ミス）は今週の実績に数えない。
                guard e.completedAt <= reference, week.contains(e.completedAt) else { continue }
                setsByMuscle[e.muscle, default: 0] += max(0, e.setCount)
            }
        }
        return RecoveryAnalyzer.trackedMuscles.map { muscle in
            Status(muscle: muscle, sets: setsByMuscle[muscle] ?? 0, targetSets: targetSets(for: muscle))
        }
    }

    /// 今週の合計セット数（対象部位ぶん）。
    static func totalSets(_ statuses: [Status]) -> Int {
        statuses.reduce(0) { $0 + $1.sets }
    }

    /// 今週まだ手つかずの部位（`trackedMuscles` の順）。
    static func untouched(_ statuses: [Status]) -> [MuscleGroup] {
        statuses.filter(\.isUntouched).map(\.muscle)
    }
}
