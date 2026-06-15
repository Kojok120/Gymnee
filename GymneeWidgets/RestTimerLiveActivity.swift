import WidgetKit
import SwiftUI
import ActivityKit

/// レストタイマー Live Activity（§6.10）。ロック画面＋Dynamic Island。
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerActivityAttributes.self) { context in
            // ロック画面 / バナー
            HStack(spacing: 12) {
                Image(systemName: "timer").font(.title2).foregroundStyle(widgetGreen)
                VStack(alignment: .leading) {
                    Text("レスト中 · \(context.state.exerciseName)").font(.caption).foregroundStyle(.secondary)
                    Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                        .font(.title2.monospacedDigit().bold())
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("レスト", systemImage: "timer").foregroundStyle(widgetGreen)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                        .monospacedDigit().frame(width: 60)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.exerciseName).font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(widgetGreen)
            } compactTrailing: {
                Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                    .monospacedDigit().frame(width: 44)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(widgetGreen)
            }
        }
    }
}
