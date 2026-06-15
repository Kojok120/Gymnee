import SwiftUI
import SwiftData

/// 設定（§5 / §7）。HealthKit・通知・エクスポート・サブスク・データ削除の各導線。
/// P0 ではプロフィール・同期状態・サインアウト・データ削除を実装。各機能は対応フェーズで有効化する。
struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(HealthKitService.self) private var health
    @Environment(\.modelContext) private var context
    @State private var showDeleteConfirm = false

    var body: some View {
        Form {
            Section("プロフィール") {
                LabeledContent("表示名", value: auth.session?.displayName ?? "—")
                if let id = auth.currentUserId {
                    LabeledContent("ユーザーID") {
                        Text(id.uuidString.prefix(8) + "…")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("同期") {
                LabeledContent("未同期の変更", value: "\(sync.pendingCount) 件")
                Text("v0 はオフラインのみ。Supabase 接続後に自動同期します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("データ") {
                Button {
                    Task { await health.requestAuthorization() }
                } label: {
                    HStack {
                        Label("ヘルスケア連携", systemImage: "heart.fill")
                        Spacer()
                        Text(health.isAvailable ? (health.isAuthorized ? "許可済み" : "許可する") : "非対応")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
                .disabled(!health.isAvailable)

                if let uid = auth.currentUserId {
                    NavigationLink {
                        AnalyticsView(userId: uid)
                    } label: {
                        Label("分析・CSVエクスポート", systemImage: "chart.bar.xaxis")
                    }
                }
            }

            Section("プラン") {
                LabeledContent("現在のプラン", value: "Free")
                Text("サブスク採用可否は要決定（§9-5）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("サインアウト", role: .destructive) {
                    auth.signOut()
                }
                Button("すべてのデータを削除", role: .destructive) {
                    showDeleteConfirm = true
                }
            } footer: {
                Text("個人情報保護法（APPI）準拠：データの削除・エクスポートを提供します（§7）。")
            }

            Section {
                LabeledContent("バージョン", value: appVersion)
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("すべてのデータを削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("削除する", role: .destructive) { deleteAllData() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この端末上の全記録が消えます。元に戻せません。")
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    /// ローカルデータの全削除（§7 データ削除）。
    private func deleteAllData() {
        try? context.delete(model: Profile.self)
        try? context.delete(model: Gym.self)
        try? context.delete(model: GymEquipment.self)
        try? context.delete(model: Visit.self)
        try? context.delete(model: VisitPartner.self)
        try? context.delete(model: Workout.self)
        try? context.delete(model: Exercise.self)
        try? context.delete(model: WorkoutExercise.self)
        try? context.delete(model: ExerciseSet.self)
        try? context.delete(model: Routine.self)
        try? context.delete(model: RoutineExercise.self)
        try? context.delete(model: PersonalRecord.self)
        try? context.delete(model: BodyMetric.self)
        try? context.delete(model: ProgressPhoto.self)
        try? context.delete(model: Follow.self)
        try? context.delete(model: FeedItem.self)
        try? context.delete(model: Product.self)
        try? context.delete(model: Order.self)
        try? context.delete(model: OrderItem.self)
        try? context.delete(model: SupplyLog.self)
        try? context.delete(model: Subscription.self)
        try? context.save()
        auth.signOut()
    }
}
