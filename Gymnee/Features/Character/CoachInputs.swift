import Foundation

/// 記録 → コーチに渡す要約（`CoachBrief`）の組み立て。
///
/// `CharacterInputs` と同じ役割で、SwiftData のモデルからドメインの入力を作る層。
/// **ここで渡さなかった情報はコーチが知り得ない**ので、何を渡すかは意図して決める。
/// 名前・メール・写真といった個人が特定できるものは一切含めない。
enum CoachInputs {

    /// 直近の記録を何件まで渡すか。多いほど文脈は増えるが、費用と応答時間も増える。
    static let recentSessionLimit = 8
    /// 直近の自己ベストを何件まで渡すか。
    static let recentRecordLimit = 5

    static func brief(
        workouts: [Workout],
        records: [PersonalRecord],
        weeklyGoal: Int,
        streakWeeks: Int,
        todayPlan: PlannedWorkout?,
        todayEvents: [String] = [],
        sleepHours: Double? = nil,
        restingHeartRate: Double? = nil,
        /// 育成のいまの値。渡さないとコーチはパワーやレベルの話に答えられない。
        growth: CharacterInputs.Growth? = nil,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> CoachBrief {
        let completed = workouts
            .compactMap { workout -> (Workout, Date)? in
                guard let done = workout.completedAt else { return nil }
                return (workout, done)
            }
            .sorted { $0.1 > $1.1 }

        let today = calendar.startOfDay(for: now)
        let activeDays = completed.map(\.1)

        let sessions = completed.prefix(recentSessionLimit).map { workout, done -> CoachBrief.Session in
            var sets = 0
            var volume: Double = 0
            var muscles: Set<String> = []
            for we in workout.exercises {
                if let group = we.exercise?.muscleGroup { muscles.insert(group.label) }
                for set in we.sets {
                    sets += 1
                    if set.volume.isFinite, set.volume > 0 { volume += set.volume }
                }
            }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: done), to: today).day ?? 0
            return CoachBrief.Session(
                daysAgo: max(0, days),
                title: workout.name,
                totalSets: sets,
                volumeKg: volume,
                muscles: muscles.sorted()
            )
        }

        return CoachBrief(
            weeklyDone: activeDays.filter { calendar.isDate($0, equalTo: now, toGranularity: .weekOfYear) }.count,
            weeklyGoal: weeklyGoal,
            streakWeeks: streakWeeks,
            recordedToday: activeDays.contains { calendar.isDate($0, inSameDayAs: today) },
            daysSinceLastWorkout: activeDays.max().map {
                max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: today).day ?? 0)
            },
            recentSessions: Array(sessions),
            fatigueByMuscle: fatigue(from: completed.map(\.0), asOf: now),
            recentRecords: recentRecordLabels(records),
            sleepHours: sleepHours,
            restingHeartRate: restingHeartRate,
            todayEvents: todayEvents,
            todayPlanTitle: todayPlan?.title,
            energy: growth?.energy,
            level: growth?.level.value,
            stageTitle: growth?.stage.title,
            nextStageUnmet: growth?.nextStage?.unmet ?? []
        )
    }

    /// 部位ごとの疲労。既存の `MuscleFatigue` をそのまま使い、コーチ用に名前と数値へ均す。
    static func fatigue(from workouts: [Workout], asOf now: Date) -> [String: Double] {
        var entries: [MuscleFatigue.SessionEntry] = []
        for workout in workouts {
            guard let done = workout.completedAt else { continue }
            var setsByGroup: [MuscleGroup: Int] = [:]
            for we in workout.exercises {
                guard let group = we.exercise?.muscleGroup else { continue }
                setsByGroup[group, default: 0] += we.sets.count
            }
            for (group, count) in setsByGroup where count > 0 {
                entries.append(MuscleFatigue.SessionEntry(muscle: group, completedAt: done, setCount: count))
            }
        }
        var result: [String: Double] = [:]
        for status in MuscleFatigue.statuses(entries: entries, asOf: now) where status.fatigue > 0.05 {
            result[status.muscle.label] = status.fatigue
        }
        return result
    }

    /// 直近の自己ベストを「種目 種別 値」の一行にする。
    /// 関連（`exercise`）は削除済みの参照を踏むと落ちるので、名前は安全に読む。
    static func recentRecordLabels(_ records: [PersonalRecord]) -> [String] {
        records
            .sorted { $0.achievedAt > $1.achievedAt }
            .prefix(recentRecordLimit)
            .map { record in
                let name = record.exercise?.name ?? "種目"
                let value = record.value.isFinite ? Int(record.value.rounded()) : 0
                return "\(name) \(record.type.label) \(value)"
            }
    }
}
