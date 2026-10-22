import WidgetKit
import SwiftUI
import ActivityKit

/// レストタイマー Live Activity（§6.10）。ロック画面＋Dynamic Island。
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerActivityAttributes.self) { context in
            // ロック画面 / バナー。息を整えている自分のキャラと、残り時間のゲージ（issue #155）。
            HStack(spacing: 12) {
                RestCharacter()
                    .frame(width: 44, height: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text("レスト中 · \(context.state.exerciseName)").font(.caption).foregroundStyle(.secondary)
                    Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                        .font(.title2.monospacedDigit().bold())
                    if let start = context.state.startDate, start < context.state.endDate {
                        ProgressView(timerInterval: start...context.state.endDate, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(widgetGreen)
                    }
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        RestCharacter().frame(width: 28, height: 32)
                        Text("レスト").font(.caption.bold()).foregroundStyle(widgetGreen)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                        .monospacedDigit().frame(width: 60)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.exerciseName).font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                RestCharacter(compact: true)
            } compactTrailing: {
                Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                    .monospacedDigit().frame(width: 44)
            } minimal: {
                RestCharacter(compact: true)
            }
        }
    }
}

/// レスト中のキャラ（本体が描いた絵）。絵がまだ無いときはタイマーのアイコンに戻す（issue #155）。
private struct RestCharacter: View {
    var compact = false

    var body: some View {
        if let url = WidgetArtwork.fileURL(WidgetArtwork.characterFile), FileManager.default.fileExists(atPath: url.path) {
            ZStack(alignment: .topTrailing) {
                ArtworkImage(fileName: WidgetArtwork.characterFile)
                if !compact {
                    // 息を整えている。
                    Text("ふぅ").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).offset(x: 6, y: -2)
                }
            }
        } else {
            Image(systemName: "timer").foregroundStyle(widgetGreen)
        }
    }
}
