import SwiftUI

/// カレンダーホーム（§6.2）。P1 で月/週表示・来店マーカー・ヒートマップ・連続記録を実装する。
/// P0 ではナビ骨格と設定導線のみ。
struct CalendarHomeView: View {
    var body: some View {
        NavigationStack {
            ComingSoonView(title: "カレンダー", systemImage: "calendar", note: "P1 で月/週表示・来店マーカー・連続記録を実装します。")
                .navigationTitle("Gymnee")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
        }
    }
}
