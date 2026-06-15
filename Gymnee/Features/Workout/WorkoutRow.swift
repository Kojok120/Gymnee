import SwiftUI

/// ワークアウト 1 件の行表示。日別詳細・一覧で共用。
struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(workout.completedAt != nil ? Theme.energy : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name).font(.subheadline.bold())
                Text("\(workout.exercises.count)種目・\(totalSets)セット")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if workout.isPlanned && workout.completedAt == nil {
                Text("予定")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        workout.completedAt != nil ? "checkmark.circle.fill" : (workout.isPlanned ? "calendar.badge.clock" : "dumbbell.fill")
    }

    private var totalSets: Int {
        workout.exercises.reduce(0) { $0 + $1.sets.count }
    }
}
