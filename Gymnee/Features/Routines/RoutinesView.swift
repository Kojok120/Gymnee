import SwiftUI
import SwiftData

/// ルーティン管理（§6.5 ルーティン/テンプレ）。
struct RoutinesView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.name) private var routines: [Routine]
    @State private var editing: Routine?
    @State private var showTemplates = false

    init(userId: UUID) {
        self.userId = userId
        _routines = Query(filter: #Predicate<Routine> { $0.userId == userId }, sort: \Routine.name)
    }

    var body: some View {
        List {
            ForEach(routines) { routine in
                Button {
                    editing = routine
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
                    Button("削除", role: .destructive) {
                        context.delete(routine)
                        try? context.save()
                    }
                }
            }
        }
        .overlay {
            if routines.isEmpty {
                EmptyStateView(systemImage: "list.bullet.rectangle", title: "ルーティンがありません", message: "右上の＋でテンプレを作成できます。")
            }
        }
        .navigationTitle("ルーティン")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { createRoutine() } label: { Label("空のルーティン", systemImage: "doc") }
                    Button { showTemplates = true } label: { Label("テンプレから作成", systemImage: "square.grid.2x2") }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { routine in
            RoutineEditorView(routine: routine)
        }
        .sheet(isPresented: $showTemplates) {
            templatePicker
        }
    }

    private var templatePicker: some View {
        NavigationStack {
            List(RoutineTemplates.all) { template in
                Button {
                    let routine = RoutineTemplates.create(template, userId: userId, context: context)
                    showTemplates = false
                    editing = routine
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
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { showTemplates = false } }
            }
        }
    }

    private func createRoutine() {
        let routine = Routine(userId: userId, name: "新しいルーティン")
        context.insert(routine)
        try? context.save()
        editing = routine
    }
}
