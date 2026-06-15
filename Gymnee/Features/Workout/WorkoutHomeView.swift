import SwiftUI

/// ワークアウトのハブ（§6.5）。P2 でルーティン開始・セッション一覧を実装する。
struct WorkoutHomeView: View {
    var body: some View {
        NavigationStack {
            ComingSoonView(title: "ワークアウト記録", systemImage: "dumbbell.fill", note: "P2 で L3 ログ（前回値オートフィル・PR検出・1RM・プレート計算）を実装します。")
                .navigationTitle("記録")
        }
    }
}
