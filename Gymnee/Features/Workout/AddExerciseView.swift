import SwiftUI
import SwiftData

/// カスタム種目作成（§6.5 種目マスタはプリセット＋ユーザー作成）。
struct AddExerciseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync

    @State private var name = ""
    @State private var muscleGroup: MuscleGroup = .chest
    @State private var equipment: EquipmentType = .barbell

    var body: some View {
        NavigationStack {
            Form {
                Section("種目名") {
                    TextField("例: ランドマインプレス", text: $name)
                }
                Section("部位") {
                    Picker("部位", selection: $muscleGroup) {
                        ForEach(MuscleGroup.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Section("器具") {
                    Picker("器具", selection: $equipment) {
                        ForEach(EquipmentType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
            }
            .navigationTitle("カスタム種目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let exercise = Exercise(
            name: name.trimmingCharacters(in: .whitespaces),
            muscleGroup: muscleGroup,
            equipment: equipment,
            isCustom: true,
            createdBy: auth.currentUserId
        )
        context.insert(exercise)
        try? context.save()
        sync.enqueue(PendingChange(entity: "exercises", recordId: exercise.id, operation: .upsert, updatedAt: exercise.updatedAt))
        dismiss()
    }
}
