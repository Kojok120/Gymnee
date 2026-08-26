import Foundation

/// リカバリービュー（§6.8）。直近で鍛えた部位を可視化し、回復済み＝次やる候補を提示する。純粋ロジックでテスト対象。
enum RecoveryAnalyzer {
    /// リカバリー対象の主要部位（全身は除く）。
    static let trackedMuscles: [MuscleGroup] = [.chest, .back, .legs, .shoulders, .arms, .abs, .core, .glutes]

    /// 部位ごとの推奨回復時間（時間）。大筋群ほど長め。
    static func recoveryHours(for muscle: MuscleGroup) -> Double {
        switch muscle {
        case .legs, .back, .glutes: return 72
        case .chest, .shoulders: return 60
        case .arms, .abs, .core: return 48
        case .fullBody: return 60
        case .cardio, .other: return 24
        }
    }

    struct MuscleStatus: Equatable, Identifiable {
        let muscle: MuscleGroup
        let lastTrained: Date?
        let hoursSince: Double?
        let recoveryHours: Double
        var id: String { muscle.rawValue }

        /// 未訓練 or 回復時間を超過していれば回復済み。
        var isRecovered: Bool {
            guard let hoursSince else { return true }
            return hoursSince >= recoveryHours
        }

        /// 回復進捗 0.0〜1.0（未訓練は 1.0）。
        var recoveryProgress: Double {
            guard let hoursSince else { return 1.0 }
            return min(hoursSince / recoveryHours, 1.0)
        }
    }

    /// 各部位の回復状況。`lastTrained` に無い部位は「未訓練（回復済み候補）」扱い。
    static func statuses(lastTrained: [MuscleGroup: Date], asOf reference: Date = .now) -> [MuscleStatus] {
        trackedMuscles.map { muscle in
            let recovery = recoveryHours(for: muscle)
            if let last = lastTrained[muscle] {
                let hours = reference.timeIntervalSince(last) / 3600.0
                return MuscleStatus(muscle: muscle, lastTrained: last, hoursSince: max(0, hours), recoveryHours: recovery)
            } else {
                return MuscleStatus(muscle: muscle, lastTrained: nil, hoursSince: nil, recoveryHours: recovery)
            }
        }
    }

}
