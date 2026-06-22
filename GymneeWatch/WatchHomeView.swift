import SwiftUI

/// Watch ホーム（§6.10）。連続日数・最終ワークアウト表示とクイックチェックイン。
struct WatchHomeView: View {
    @State private var snapshot = GymneeSnapshot.empty
    @State private var checkedIn = false

    private let watchGreen = Color(red: 0.45, green: 0.85, blue: 0.25)

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                    Text("\(snapshot.streak)").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(watchGreen)
                    Text("日連続").font(.caption2).foregroundStyle(.secondary)
                }

                Text("今週 \(snapshot.weeklyCount)/\(snapshot.weeklyGoal)")
                    .font(.caption)
                if let last = snapshot.lastWorkoutName {
                    Text("最終: \(last)").font(.caption2).foregroundStyle(.secondary)
                }

                Button {
                    // App Group は端末間で同期しないため、本体へは WCSession 経由で送る。
                    WatchConnector.shared.sendCheckIn()
                    checkedIn = true
                } label: {
                    Label(checkedIn ? "リクエスト済み" : "クイックチェックイン", systemImage: checkedIn ? "checkmark" : "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(watchGreen)
                .disabled(checkedIn)

                Label("心拍 -- bpm", systemImage: "heart.fill")
                    .font(.caption2).foregroundStyle(.pink)
            }
            .padding()
        }
        .onAppear { snapshot = SharedStore.load() }
        .onReceive(NotificationCenter.default.publisher(for: .gymneeSnapshotUpdated)) { _ in
            snapshot = SharedStore.load()
        }
    }
}
