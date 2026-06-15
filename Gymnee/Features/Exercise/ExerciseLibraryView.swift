import SwiftUI
import SwiftData

/// 種目ライブラリ（§5）。種目一覧から種目詳細（推移・PR・履歴）へ。
struct ExerciseLibraryView: View {
    let userId: UUID

    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var showAdd = false

    var body: some View {
        List {
            ForEach(grouped.keys.sorted(by: { $0.label < $1.label }), id: \.self) { mg in
                Section(mg.label) {
                    ForEach(grouped[mg] ?? []) { exercise in
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise, userId: userId)
                        } label: {
                            HStack {
                                Text(exercise.name)
                                Spacer()
                                Text(exercise.equipment.label).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "種目を検索")
        .navigationTitle("種目ライブラリ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddExerciseView() }
    }

    private var filtered: [Exercise] {
        search.isEmpty ? exercises : exercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var grouped: [MuscleGroup: [Exercise]] {
        Dictionary(grouping: filtered, by: { $0.muscleGroup })
    }
}
