import Foundation
import ActivityKit

/// レストタイマー Live Activity の属性（§6.10）。アプリ本体と Widget 拡張で共有する。
struct RestTimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var endDate: Date
        var exerciseName: String
    }

    var workoutName: String
}
