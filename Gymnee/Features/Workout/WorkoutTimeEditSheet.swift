import SwiftUI
import SwiftData

/// 完了済みワークアウトの開始時刻・所要時間を手動で登録/修正するシート。
/// 筋トレ後にまとめて記録した場合や過去日の後追い記録では自動計測の総合時間が
/// 実態と合わないため、ここで実際の時間に直す（日付は記録日のまま時刻だけ動かす）。
/// 保存時はサーバー同期に加え、公開済みフィードの stats も再発行して追従させる。
struct WorkoutTimeEditSheet: View {
    let workout: Workout

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(AppErrorCenter.self) private var errors
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.friends.rawValue

    @State private var start: Date
    @State private var hours: Int
    @State private var minutes: Int

    init(workout: Workout) {
        self.workout = workout
        _start = State(initialValue: workout.date)
        let mins = WorkoutDuration.minutes(
            date: workout.date, completedAt: workout.completedAt, durationSeconds: workout.durationSeconds
        ) ?? 0
        _hours = State(initialValue: mins / 60)
        _minutes = State(initialValue: mins % 60)
    }

    private var totalSeconds: Int { hours * 3600 + minutes * 60 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("開始時刻", selection: $start, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("日付は記録日のまま変わりません。")
                }
                Section("所要時間") {
                    HStack(spacing: 0) {
                        Picker("時間", selection: $hours) {
                            ForEach(0..<13) { Text("\($0)時間").tag($0) }
                        }
                        Picker("分", selection: $minutes) {
                            ForEach(0..<60) { Text("\($0)分").tag($0) }
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                    .labelsHidden()
                }
            }
            .navigationTitle("時間を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }.disabled(totalSeconds <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// 開始時刻＋所要時間を確定し、完了時刻は「開始＋所要」で揃える
    /// （アナリティクス/ストリークの日付判定を開始日と矛盾させない）。
    private func save() {
        workout.date = start
        workout.durationSeconds = totalSeconds
        workout.completedAt = start.addingTimeInterval(TimeInterval(totalSeconds))
        workout.updatedAt = .now
        workout.isDirty = true
        do {
            try context.save()
        } catch {
            errors.report("時間を保存できませんでした。\(error.localizedDescription)")
            return
        }
        sync.enqueue(PendingChange(entity: "workouts", recordId: workout.id, operation: .upsert, updatedAt: workout.updatedAt))
        // 公開済みならフィードの「時間」stat を新しい値へ追従させる（未公開なら何も作らない）。
        FeedPublisher.syncPublishedPosts(userId: workout.userId, authorName: auth.session?.displayName, context: context, sync: sync)
        dismiss()
    }
}
