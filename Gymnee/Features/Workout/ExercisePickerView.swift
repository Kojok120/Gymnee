import SwiftUI

/// 種目ピッカー（記録画面「その他」カードの遷移先）。検索＋部位フィルタ＋カスタム種目作成。
/// 選んだ/作った種目は onSelect で呼び出し側（タブのシェルフ）へ渡す。
/// 旧「種目を選んで追加する」フローの廃止で一時デッドコードだったが、
/// 2026-07 のタブフィルタ改修（シェルフへの追加導線）で復活した。
struct ExercisePickerView: View {
    /// 表示する種目（呼び出し側で同名重複を解決済みの一覧を渡す）。
    let exercises: [Exercise]
    var onSelect: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var muscleFilter: MuscleGroup?
    @State private var showAdd = false

    init(exercises: [Exercise], initialFilter: MuscleGroup? = nil, onSelect: @escaping (Exercise) -> Void) {
        self.exercises = exercises
        self.onSelect = onSelect
        // 開いたタブの部位を初期フィルタにする（探す種目は大抵その部位のため）。
        _muscleFilter = State(initialValue: initialFilter)
    }

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
            // 見つからなければその場で作成 → 即選択（開いていたタブへ追加される）。
            .sheet(isPresented: $showAdd) {
                AddExerciseView(onCreated: { ex in
                    onSelect(ex)
                    dismiss()
                })
            }
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
                .background(selected ? Theme.textPrimary : Theme.bg2, in: Capsule())
                .foregroundStyle(selected ? Theme.bg0 : Theme.textSecondary)
        }
    }

    private var filtered: [Exercise] {
        exercises.filter { ex in
            (muscleFilter == nil || ex.muscleGroup == muscleFilter) &&
            (search.isEmpty || ex.name.localizedCaseInsensitiveContains(search))
        }
    }
}
