import SwiftUI
import SwiftData

/// ルーティン管理（§6.5 ルーティン/テンプレ）。
struct RoutinesView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.name) private var routines: [Routine]
    @State private var editing: Routine?

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
                Button { createRoutine() } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { routine in
            RoutineEditorView(routine: routine)
        }
    }

    private func createRoutine() {
        let routine = Routine(userId: userId, name: "新しいルーティン")
        context.insert(routine)
        try? context.save()
        editing = routine
    }
}
