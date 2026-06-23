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
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text(re.exercise?.name ?? "種目")
                                .font(.headline)
                                .lineLimit(1).truncationMode(.tail)
                            stepperRow(icon: "square.stack.3d.up.fill", label: "セット",
                                       value: "\(re.targetSets)", binding: bindingTargetSets(re), range: 1...10)
                            stepperRow(icon: "repeat", label: "目標レップ",
                                       value: "\(re.targetReps ?? 10) 回", binding: bindingTargetReps(re), range: 1...50)
                            stepperRow(icon: "timer", label: "レスト",
                                       value: "\(re.restSeconds ?? 90) 秒", binding: bindingRest(re), range: 30...300, step: 15)
                        }
                        .padding(.vertical, Theme.Spacing.xs)
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
                    Text("ドラッグで並べ替え、種目別に目標セット数・目標レップ・レスト時間を設定できます。")
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

    /// 種目ごとの設定行（アイコン＋ラベル左、値＋コンパクトStepper右）。整然と揃える。
    private func stepperRow(icon: String, label: String, value: String, binding: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: Theme.Spacing.sm)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Stepper("", value: binding, in: range, step: step)
                .labelsHidden()
                .fixedSize()
        }
    }

    private func bindingTargetSets(_ re: RoutineExercise) -> Binding<Int> {
        Binding(get: { re.targetSets }, set: { re.targetSets = $0; re.updatedAt = .now })
    }

    private func bindingTargetReps(_ re: RoutineExercise) -> Binding<Int> {
        Binding(get: { re.targetReps ?? 10 }, set: { re.targetReps = $0; re.updatedAt = .now })
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
        // 参照する種目もサーバーへ（FK: routine_exercises.exercise_id）。
        sync.enqueue(PendingChange(entity: "exercises", recordId: exercise.id, operation: .upsert, updatedAt: exercise.updatedAt))
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
