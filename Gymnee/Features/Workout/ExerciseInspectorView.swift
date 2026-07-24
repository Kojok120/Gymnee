import SwiftUI
import SwiftData

/// 種目カードのタップで開く詳細ページ（記録リデザイン）。
/// 「記録」タブ＝種目詳細（推定1RM推移・自己ベスト・次回の目安・履歴。履歴は新しい順/古い順ソート可）、
/// 「設定」タブ＝種目の編集（名前・部位・器具・計測タイプ・片側/両側・削除）。
struct ExerciseInspectorView: View {
    @Bindable var exercise: Exercise
    let userId: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @State private var tab = 0   // 0=記録, 1=設定

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("記録").tag(0)
                    Text("設定").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)

                if tab == 0 {
                    ExerciseDetailView(exercise: exercise, userId: userId)
                } else {
                    ExerciseSettingsForm(exercise: exercise)
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完了") { save() }.bold() }
            }
        }
    }

    /// 設定タブの編集を保存（@Bindable でライブ反映済みの値を永続化＋同期）して閉じる。
    private func save() {
        exercise.updatedAt = .now
        exercise.isDirty = true
        try? context.save()
        sync.enqueue(PendingChange(entity: "exercises", recordId: exercise.id, operation: .upsert, updatedAt: exercise.updatedAt))
        dismiss()
    }
}

/// 種目の設定編集フォーム（インスペクタ「設定」タブ本体）。
/// 保存は親（ExerciseInspectorView の「完了」）が担う。削除は本フォームで実行しページを閉じる。
struct ExerciseSettingsForm: View {
    @Bindable var exercise: Exercise

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalSyncEngine.self) private var sync
    @State private var showDeleteConfirm = false

    var body: some View {
        Form {
            Section("種目名") {
                TextField("種目名", text: $exercise.name)
            }
            Section("部位") {
                Picker("部位", selection: Binding(get: { exercise.muscleGroup }, set: { exercise.muscleGroup = $0 })) {
                    ForEach(MuscleGroup.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section("器具") {
                Picker("器具", selection: Binding(get: { exercise.equipment }, set: { exercise.equipment = $0 })) {
                    ForEach(EquipmentType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section {
                Picker("計測タイプ", selection: Binding(get: { exercise.measurementType }, set: { exercise.measurementType = $0 })) {
                    ForEach(MeasurementType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } header: {
                Text("計測タイプ")
            } footer: {
                Text("ウェイト＝重量×回数 / 自重＝加重×回数 / 時間＝秒。")
            }
            if exercise.measurementType == .weight {
                Section {
                    Picker("重量の数え方", selection: Binding(get: { exercise.weightMode }, set: { exercise.weightMode = $0 })) {
                        ForEach(WeightMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text("ダンベル等は「片側」。合計挙上量の計算に使います。")
                }
            }
            if exercise.measurementType == .bodyweight {
                Section {
                    Picker("荷重", selection: Binding(get: { exercise.loadMode }, set: { exercise.loadMode = $0 })) {
                        ForEach(LoadMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("荷重モード")
                } footer: {
                    Text("懸垂・ディップス等で「荷重（自重＋kg）」と「補助（自重−kg・バンド/アシストマシン）」を区別します。自重のみは回数だけ記録。自己ベストは 荷重=最大荷重 / 補助=最小補助 / 自重=最大回数。")
                }
            }
            Section {
                Toggle("角度あり", isOn: Binding(get: { exercise.hasAngle }, set: { exercise.hasAngle = $0 }))
            } footer: {
                Text("インクライン/デクライン等、ベンチ角度をセットごとに記録する種目でオンにします。")
            }
            if exercise.isCustom {
                Section {
                    Button("この種目を削除", role: .destructive) { showDeleteConfirm = true }
                }
            }
        }
        .confirmationDialog("この種目を削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("削除する", role: .destructive) { deleteExercise() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("過去の記録からこの種目名は外れます（記録自体は残ります）。")
        }
    }

    private func deleteExercise() {
        let id = exercise.id
        context.delete(exercise)
        try? context.save()
        sync.enqueue(PendingChange(entity: "exercises", recordId: id, operation: .delete, updatedAt: .now))
        dismiss()
    }
}
