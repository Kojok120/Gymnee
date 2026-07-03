import SwiftUI
import SwiftData

/// ルーティン管理（§6.5）。一覧で追加・編集・削除。
/// 追加/編集は隔離コンテキストで行い「完了」まで保存しない（[[RoutineEditSession]]）。
struct RoutinesView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Query(sort: \Routine.name) private var routines: [Routine]
    @State private var session: RoutineEditSession?
    @State private var showTemplates = false

    init(userId: UUID) {
        self.userId = userId
        _routines = Query(filter: #Predicate<Routine> { $0.userId == userId }, sort: \Routine.name)
    }

    var body: some View {
        List {
            ForEach(routines) { routine in
                Button {
                    session = .edit(routine.id, container: context.container)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(routine.name).foregroundStyle(.primary)
                            Text("\(routine.routineExercises.count)種目")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .swipeActions {
                    Button("削除", role: .destructive) { deleteRoutine(routine) }
                }
            }
        }
        .overlay {
            if routines.isEmpty {
                EmptyStateView(systemImage: "list.bullet.rectangle", title: "カスタムセットがありません", message: "右上の＋で追加できます。")
            }
        }
        .navigationTitle("カスタムセット")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { session = .new(userId: userId, container: context.container) } label: {
                        Label("空のカスタムセット", systemImage: "doc")
                    }
                    Button { showTemplates = true } label: {
                        Label("テンプレから作成", systemImage: "square.grid.2x2")
                    }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $session) { s in
            RoutineEditorView(routine: s.routine, editorContext: s.context, isNew: s.isNew)
        }
        .sheet(isPresented: $showTemplates) { templatePicker }
    }

    private var templatePicker: some View {
        RoutineTemplatePicker(
            onSelect: { template in
                showTemplates = false
                session = .template(template, userId: userId, container: context.container)
            },
            onCancel: { showTemplates = false }
        )
    }

    /// ルーティン削除＝本体と配下種目の削除を送出（即時。サーバ側 FK でも連鎖するが明示的に積む）。
    private func deleteRoutine(_ routine: Routine) {
        let routineId = routine.id
        let exerciseIds = routine.routineExercises.map(\.id)
        context.delete(routine)
        try? context.save()
        let pending = [PendingChange(entity: "routines", recordId: routineId, operation: .delete, updatedAt: .now)]
            + exerciseIds.map { PendingChange(entity: "routine_exercises", recordId: $0, operation: .delete, updatedAt: .now) }
        sync.enqueueBatch(pending)
    }
}

/// テンプレ一覧の選択シート（ルーティン管理と記録開始ゲートで共用）。
struct RoutineTemplatePicker: View {
    let onSelect: (RoutineTemplates.Template) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List(RoutineTemplates.all) { template in
                Button {
                    onSelect(template)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name).font(.body).foregroundStyle(.primary)
                        Text("\(template.detail)・\(template.exerciseNames.count)種目×\(template.sets)セット")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("テンプレを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { onCancel() } }
            }
        }
    }
}

