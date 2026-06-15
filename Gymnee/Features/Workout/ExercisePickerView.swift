import SwiftUI
import SwiftData

/// 種目選択（§6.5 種目追加）。検索＋部位フィルタ、カスタム種目作成。
struct ExercisePickerView: View {
    var onSelect: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var muscleFilter: MuscleGroup?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { exercise in
                    Button {
                        onSelect(exercise)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                Text("\(exercise.muscleGroup.label)・\(exercise.equipment.label)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if exercise.isCustom {
                                Text("カスタム").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
            .searchable(text: $search, prompt: "種目を検索")
            .safeAreaInset(edge: .top) { muscleFilterBar }
            .navigationTitle("種目を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddExerciseView() }
        }
    }

    private var muscleFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                chip(title: "すべて", selected: muscleFilter == nil) { muscleFilter = nil }
                ForEach(MuscleGroup.allCases, id: \.self) { mg in
                    chip(title: mg.label, selected: muscleFilter == mg) { muscleFilter = mg }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(.bar)
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 6)
                .background(selected ? Theme.energy : Color(uiColor: .tertiarySystemFill), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
    }

    private var filtered: [Exercise] {
        exercises.filter { ex in
            (muscleFilter == nil || ex.muscleGroup == muscleFilter) &&
            (search.isEmpty || ex.name.localizedCaseInsensitiveContains(search))
        }
    }
}
