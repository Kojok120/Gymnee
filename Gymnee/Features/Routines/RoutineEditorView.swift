import SwiftUI
import SwiftData

/// ルーティン編集セッション。隔離した ModelContext（autosave無効）で編集し、
/// 「完了」時のみ save する＝途中で閉じれば一切永続化しない（捨てる）。
@MainActor
struct RoutineEditSession: Identifiable {
    let id = UUID()
    let routine: Routine
    let context: ModelContext
    let isNew: Bool

    /// 新規（空のカスタムセット）。
    static func new(userId: UUID, container: ModelContainer) -> RoutineEditSession {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        let r = Routine(userId: userId, name: "新しいカスタムセット")
        ctx.insert(r)
        return .init(routine: r, context: ctx, isNew: true)
    }

    /// テンプレから新規。
    static func template(_ t: RoutineTemplates.Template, userId: UUID, container: ModelContainer) -> RoutineEditSession {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        let r = RoutineTemplates.create(t, userId: userId, context: ctx)
        return .init(routine: r, context: ctx, isNew: true)
    }

    /// 既存編集（対象を隔離コンテキストに取り込む。元データは完了まで無変更）。
    static func edit(_ routineId: UUID, container: ModelContainer) -> RoutineEditSession? {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        guard let r = (try? ctx.fetch(FetchDescriptor<Routine>(predicate: #Predicate { $0.id == routineId })))?.first else { return nil }
        return .init(routine: r, context: ctx, isNew: false)
    }
}

/// ルーティン編集（記録リデザイン）。種目と「3重量＋3reps（時間種目は3秒）」候補を構成する。
/// 隔離コンテキストで編集し、「完了」で初めて保存＋同期。キャンセル/破棄なら永続化しない。
struct RoutineEditorView: View {
    @Bindable var routine: Routine
    /// 隔離した編集用コンテキスト（保存は完了時のみ）。
    let editorContext: ModelContext
    var isNew: Bool = false

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
                    TextField("カスタムセット名", text: $routine.name)
                }
                Section {
                    ForEach(orderedExercises) { re in
                        exerciseRow(re)
                            .padding(.vertical, Theme.Spacing.xs)
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)

                    Button { showPicker = true } label: {
                        Label("種目を追加", systemImage: "plus")
                    }
                } header: {
                    HStack {
                        Text("種目")
                        Spacer()
                        EditButton().font(.caption)
                    }
                } footer: {
                    Text("重量・回数の値は記録画面のルーラーで選びます（履歴/既定から自動表示）。ここでは種目・順番・目標セット数だけ設定します。")
                }
            }
            .navigationTitle(isNew ? "新しいカスタムセット" : "カスタムセット編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }   // 保存しない＝隔離コンテキストごと破棄
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { save(); dismiss() }.bold()
                        .disabled(routine.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                AddExerciseView(onCreated: { addExercise($0) })
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func exerciseRow(_ re: RoutineExercise) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(re.exercise?.name ?? "種目")
                    .font(.headline).lineLimit(1).truncationMode(.tail)
                Spacer()
                Text(re.exercise?.measurementType.label ?? "")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Stepper(value: bindingTargetSets(re), in: 1...10) {
                Text("目標セット \(re.targetSets)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func bindingTargetSets(_ re: RoutineExercise) -> Binding<Int> {
        Binding(get: { re.targetSets }, set: { re.targetSets = $0; re.updatedAt = .now })
    }

    // MARK: - 編集アクション（すべて隔離コンテキスト上）

    private func move(_ offsets: IndexSet, _ destination: Int) {
        var items = orderedExercises
        items.move(fromOffsets: offsets, toOffset: destination)
        for (i, re) in items.enumerated() {
            re.orderIndex = i
            re.updatedAt = .now
        }
    }

    private func addExercise(_ exercise: Exercise) {
        // ピッカーは mainContext の Exercise を返すので、隔離コンテキストに取り込み直す。
        let exId = exercise.id
        let localEx = (try? editorContext.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == exId })))?.first
        let re = RoutineExercise(orderIndex: routine.routineExercises.count, targetSets: 3, routine: routine, exercise: localEx)
        editorContext.insert(re)
    }

    private func delete(_ offsets: IndexSet) {
        let items = orderedExercises
        for index in offsets {
            editorContext.delete(items[index])
        }
    }

    /// 完了：隔離コンテキストを保存し、本体＋配下種目を同期キューへ（enqueueBatch でディスク書込1回）。
    private func save() {
        routine.updatedAt = .now
        routine.isDirty = true
        try? editorContext.save()
        var pending: [PendingChange] = [PendingChange(entity: "routines", recordId: routine.id, operation: .upsert, updatedAt: routine.updatedAt)]
        for re in routine.routineExercises {
            if let ex = re.exercise {
                pending.append(PendingChange(entity: "exercises", recordId: ex.id, operation: .upsert, updatedAt: ex.updatedAt))
            }
            pending.append(PendingChange(entity: "routine_exercises", recordId: re.id, operation: .upsert, updatedAt: re.updatedAt))
        }
        sync.enqueueBatch(pending)
    }
}
