import SwiftUI

/// サインイン直後の初期設定（監査T2c / 定着）。空ダッシュボードへ直行させず、
/// 表示名・週の目標・通知を最初に確定させて「自分のゴール」と再訪導線を立ち上げる。
struct SetupOnboardingView: View {
    @Environment(AuthService.self) private var auth
    @Environment(NotificationService.self) private var notifications
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal = 3
    @AppStorage("gymnee.setupDone") private var setupDone = false
    @AppStorage("gymnee.notif.prePrompted") private var notifPrePrompted = false
    // 通知の種類別 ON/OFF（設定画面と共有）。オンボーディングのトグルはこれらをまとめて切り替える。
    @AppStorage(NotificationService.PrefKey.streak) private var notifStreak = true
    @AppStorage(NotificationService.PrefKey.planned) private var notifPlanned = true
    @AppStorage(NotificationService.PrefKey.weeklyRecap) private var notifWeeklyRecap = true
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
                    Toggle(isOn: notificationsBinding) {
                        Label("通知を受け取る", systemImage: "bell.fill")
                    }
                } footer: {
                    Text("連続記録の途切れ予告・フレンドの活動・今週のまとめをお届けします。種類ごとのオン/オフはあとから「その他 > 設定」で変更できます。")
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

    /// 通知トグル。オンで許可を要求し種類別設定を一括有効化、オフで種類別設定を一括無効化して
    /// 予約済みのローカル通知を取り消す（OS の許可自体はアプリから取り消せないため、
    /// アプリ内のスケジュールを止めるのが「オフ」の実体）。
    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { notifRequested },
            set: { on in
                notifRequested = on
                if on {
                    notifPrePrompted = true
                    notifStreak = true; notifPlanned = true; notifWeeklyRecap = true
                    Task { await notifications.requestAuthorization() }
                } else {
                    notifStreak = false; notifPlanned = false; notifWeeklyRecap = false
                    notifications.cancelStreakReminder()
                    notifications.cancelPlannedReminders()
                    notifications.cancelWeeklyRecap()
                }
            }
        )
    }

    private func finish() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { auth.updateDisplayName(trimmed) }
        setupDone = true // バインディングが false になり cover が閉じる
    }
}
