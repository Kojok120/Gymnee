import SwiftUI
import SwiftData

/// 種目の編集（記録リデザイン）。名前・部位・器具・計測タイプ・片側/両側を編集。
/// 計測タイプ：ウェイト＝重量×reps / 自重＝加重×reps / 時間＝秒。
struct ExerciseEditView: View {
    @Bindable var exercise: Exercise

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalSyncEngine.self) private var sync
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
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
                if exercise.isCustom {
                    Section {
                        Button("この種目を削除", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle("種目を編集").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { save() }.bold()
                }
            }
            .confirmationDialog("この種目を削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("削除する", role: .destructive) { deleteExercise() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("過去の記録からこの種目名は外れます（記録自体は残ります）。")
            }
        }
    }

    private func save() {
        exercise.updatedAt = .now
        exercise.isDirty = true
        try? context.save()
        sync.enqueue(PendingChange(entity: "exercises", recordId: exercise.id, operation: .upsert, updatedAt: exercise.updatedAt))
        dismiss()
    }

    private func deleteExercise() {
        let id = exercise.id
        context.delete(exercise)
        try? context.save()
        sync.enqueue(PendingChange(entity: "exercises", recordId: id, operation: .delete, updatedAt: .now))
        dismiss()
    }
}
