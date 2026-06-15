import SwiftUI

/// 分析ダッシュボード（§6.8）。P4 で強度進捗・頻度・部位バランス・リカバリービュー・CSVを実装する。
struct AnalyticsView: View {
    let userId: UUID
    var body: some View {
        ComingSoonView(title: "分析", systemImage: "chart.bar.xaxis", note: "P4 で部位バランス・リカバリービュー・CSVエクスポートを実装します。")
            .navigationTitle("分析")
            .navigationBarTitleDisplayMode(.inline)
    }
}
