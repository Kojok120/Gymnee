import WidgetKit
import SwiftUI

/// Widget 拡張のエントリ（§6.10）。ホーム/ロック画面ウィジェット＋レストタイマー Live Activity。
@main
struct GymneeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StreakWidget()
        RestTimerLiveActivity()
    }
}

/// ウィジェット共通のブランドカラー（拡張は本体 Theme に依存しない）。
let widgetGreen = Color(red: 0.45, green: 0.85, blue: 0.25)
