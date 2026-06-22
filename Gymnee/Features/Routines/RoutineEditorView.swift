import SwiftUI
import SwiftData

/// ルーティン編集（§6.5）。種目と目標セット数を構成する。
struct RoutineEditorView: View {
    @Bindable var routine: Routine

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalSyncEngine.self) private var sync
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
                Section {
                    ForEach(orderedExercises) { re in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(re.exercise?.name ?? "種目").font(.body)
                            HStack {
                                Stepper("\(re.targetSets)セット", value: bindingTargetSets(re), in: 1...10)
                                    .fixedSize()
                                Spacer()
                            }
                            HStack {
                                Image(systemName: "timer").font(.caption).foregroundStyle(.secondary)
                                Stepper("レスト \(re.restSeconds ?? 90)秒", value: bindingRest(re), in: 30...300, step: 15)
                                    .fixedSize()
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)

                    Button {
                        showPicker = true
                    } label: {
                        Label("種目を追加", systemImage: "plus")
                    }
                } header: {
                    HStack {
                        Text("種目")
                        Spacer()
                        EditButton().font(.caption)
                    }
                } footer: {
                    Text("ドラッグで並べ替え、種目別にレスト時間を設定できます。")
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

    private func bindingRest(_ re: RoutineExercise) -> Binding<Int> {
        Binding(get: { re.restSeconds ?? 90 }, set: { re.restSeconds = $0; re.updatedAt = .now })
    }

    private func move(_ offsets: IndexSet, _ destination: Int) {
        var items = orderedExercises
        items.move(fromOffsets: offsets, toOffset: destination)
        for (i, re) in items.enumerated() {
            re.orderIndex = i
            re.updatedAt = .now
        }
        try? context.save()
        for re in items {
            sync.enqueue(PendingChange(entity: "routine_exercises", recordId: re.id, operation: .upsert, updatedAt: re.updatedAt))
        }
    }

    private func addExercise(_ exercise: Exercise) {
        let re = RoutineExercise(orderIndex: routine.routineExercises.count, targetSets: 3, routine: routine, exercise: exercise)
        context.insert(re)
        try? context.save()
        sync.enqueue(PendingChange(entity: "routine_exercises", recordId: re.id, operation: .upsert, updatedAt: re.updatedAt))
    }

    private func delete(_ offsets: IndexSet) {
        let items = orderedExercises
        let removedIds = offsets.map { items[$0].id }
        for index in offsets {
            context.delete(items[index])
        }
        try? context.save()
        for id in removedIds {
            sync.enqueue(PendingChange(entity: "routine_exercises", recordId: id, operation: .delete, updatedAt: .now))
        }
    }

    private func save() {
        routine.updatedAt = .now
        routine.isDirty = true
        try? context.save()
        // 名称変更に加え、ステッパーで編集したセット数・レストも確実に送出（漏れ防止に全種目を upsert）。
        sync.enqueue(PendingChange(entity: "routines", recordId: routine.id, operation: .upsert, updatedAt: routine.updatedAt))
        for re in routine.routineExercises {
            sync.enqueue(PendingChange(entity: "routine_exercises", recordId: re.id, operation: .upsert, updatedAt: re.updatedAt))
        }
    }
}
