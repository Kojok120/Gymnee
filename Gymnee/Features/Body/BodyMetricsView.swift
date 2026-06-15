import SwiftUI

/// 身体メトリクス（§6.7）。P4 で体重・体脂肪・サイズ入力＋推移・HealthKit同期を実装する。
struct BodyMetricsView: View {
    let userId: UUID
    var body: some View {
        ComingSoonView(title: "身体メトリクス", systemImage: "ruler", note: "P4 で体重・体脂肪・サイズの記録と推移を実装します。")
            .navigationTitle("身体メトリクス")
            .navigationBarTitleDisplayMode(.inline)
    }
}
