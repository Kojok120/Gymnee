import SwiftUI

/// サインイン直後の初期設定（監査T2c / 定着）。空ダッシュボードへ直行させず、
/// 表示名・週の目標・通知を最初に確定させて「自分のゴール」と再訪導線を立ち上げる。
struct SetupOnboardingView: View {
    @Environment(AuthService.self) private var auth
    @Environment(NotificationService.self) private var notifications
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal = 3
    @AppStorage("gymnee.setupDone") private var setupDone = false
    @AppStorage("gymnee.notif.prePrompted") private var notifPrePrompted = false
    @State private var name = ""
    @State private var notifRequested = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "dumbbell.fill").font(.system(size: 44)).foregroundStyle(Theme.lime)
                        Text("ようこそ Gymnee へ").font(.title3.bold())
                        Text("最初に少しだけ設定しましょう。").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section("表示名") {
                    TextField("表示名（フレンドに表示されます）", text: $name)
                }
                Section {
                    Stepper(value: $weeklyGoal, in: 1...7) {
                        LabeledContent("週のワークアウト目標", value: "\(weeklyGoal) 日")
                    }
                } header: {
                    Text("今週の目標")
                } footer: {
                    Text("ホームの「今週の達成」リングの目標になります。")
                }
                Section {
                    Button {
                        notifRequested = true
                        notifPrePrompted = true
                        Task { await notifications.requestAuthorization() }
                    } label: {
                        Label(notifRequested ? "通知を設定しました" : "通知をオンにする", systemImage: notifRequested ? "checkmark.circle.fill" : "bell.fill")
                    }
                    .disabled(notifRequested)
                } footer: {
                    Text("連続記録の途切れ予告・フレンドの活動・今週のまとめをお届けします。")
                }
            }
            .navigationTitle("はじめに")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("始める") { finish() }.bold() }
            }
            .onAppear { if name.isEmpty { name = auth.session?.displayName ?? "" } }
        }
        .interactiveDismissDisabled()
    }

    private func finish() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { auth.updateDisplayName(trimmed) }
        setupDone = true // バインディングが false になり cover が閉じる
    }
}
