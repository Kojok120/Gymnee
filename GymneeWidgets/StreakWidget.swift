import WidgetKit
import SwiftUI

/// 連続日数・最終ワークアウト・次の予定ウィジェット（§6.10）。
struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StreakWidget", provider: SnapshotProvider()) { entry in
            StreakWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Gymnee 連続記録")
        .description("連続日数・最終ワークアウト・次の予定を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: GymneeSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: GymneeSnapshot(streak: 5, weeklyCount: 2, lastWorkoutName: "胸・三頭"))
    }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: SharedStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: SharedStore.load())
        let next = Calendar.current.date(byAdding: .hour, value: 3, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: GymneeSnapshot

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(snapshot.streak)日連続", systemImage: "flame.fill")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("\(snapshot.streak)日連続", systemImage: "flame.fill").font(.headline)
                Text("今週 \(snapshot.weeklyCount)/\(snapshot.weeklyGoal)")
                if let last = snapshot.lastWorkoutName { Text(last).font(.caption2) }
            }
        case .systemMedium:
            HStack {
                streakBlock
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    detailRow("最終", snapshot.lastWorkoutName ?? "—")
                    detailRow("次の予定", snapshot.nextPlannedName ?? "未設定")
                    detailRow("今週", "\(snapshot.weeklyCount)/\(snapshot.weeklyGoal)")
                }
                .font(.caption)
                Spacer()
            }
        default:
            streakBlock
        }
    }

    private var streakBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "flame.fill").foregroundStyle(.orange)
            Text("\(snapshot.streak)").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(widgetGreen)
            Text("日連続").font(.caption).foregroundStyle(.secondary)
            Text("今週 \(snapshot.weeklyCount)/\(snapshot.weeklyGoal)").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold().lineLimit(1)
        }
    }
}
