import Foundation

/// ボリューム集計（§6.5 / §6.8）。週あたり部位別ボリュームなど。純粋ロジックでテスト対象。
/// SwiftData に依存しないよう、集計入力は値型 `VolumeEntry` で受ける。
enum VolumeCalculator {
    struct VolumeEntry: Sendable {
        let muscleGroup: MuscleGroup
        let weight: Double
        let reps: Int
        let date: Date

        var volume: Double { weight * Double(reps) }
    }

    /// 合計ボリューム。
    static func totalVolume(_ entries: [VolumeEntry]) -> Double {
        entries.reduce(0) { $0 + $1.volume }
    }

    /// 部位別ボリューム。
    static func volumeByMuscle(_ entries: [VolumeEntry]) -> [MuscleGroup: Double] {
        var result: [MuscleGroup: Double] = [:]
        for entry in entries {
            result[entry.muscleGroup, default: 0] += entry.volume
        }
        return result
    }

    /// 指定週（reference を含む週）の部位別ボリューム。
    static func weeklyVolumeByMuscle(_ entries: [VolumeEntry], in reference: Date = .now, calendar: Calendar = .current) -> [MuscleGroup: Double] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: reference) else { return [:] }
        let inWeek = entries.filter { week.contains($0.date) }
        return volumeByMuscle(inWeek)
    }

    /// 部位別の総セット数。部位バランス可視化に使用。
    static func setCountByMuscle(_ entries: [VolumeEntry]) -> [MuscleGroup: Int] {
        var result: [MuscleGroup: Int] = [:]
        for entry in entries {
            result[entry.muscleGroup, default: 0] += 1
        }
        return result
    }
}
