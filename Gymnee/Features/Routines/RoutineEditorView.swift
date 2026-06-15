import SwiftUI
import SwiftData

/// ルーティン編集（§6.5）。種目と目標セット数を構成する。
struct RoutineEditorView: View {
    @Bindable var routine: Routine

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false

    private var orderedExercises: [RoutineExercise] {
        routine.routineExercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("ルーティン名", text: $routine.name)
                }
                Section("種目") {
                    ForEach(orderedExercises) { re in
                        HStack {
                            Text(re.exercise?.name ?? "種目")
                            Spacer()
                            Stepper("\(re.targetSets)セット", value: bindingTargetSets(re), in: 1...10)
                                .fixedSize()
                        }
                    }
                    .onDelete(perform: delete)

                    Button {
                        showPicker = true
                    } label: {
                        Label("種目を追加", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("ルーティン編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { save(); dismiss() }.bold()
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView { addExercise($0) }
            }
        }
    }

    private func bindingTargetSets(_ re: RoutineExercise) -> Binding<Int> {
        Binding(get: { re.targetSets }, set: { re.targetSets = $0; re.updatedAt = .now })
    }

    private func addExercise(_ exercise: Exercise) {
        let re = RoutineExercise(orderIndex: routine.routineExercises.count, targetSets: 3, routine: routine, exercise: exercise)
        context.insert(re)
        try? context.save()
    }

    private func delete(_ offsets: IndexSet) {
        let items = orderedExercises
        for index in offsets {
            context.delete(items[index])
        }
        try? context.save()
    }

    private func save() {
        routine.updatedAt = .now
        routine.isDirty = true
        try? context.save()
    }
}
