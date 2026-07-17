import SwiftUI

/// 種目ピッカー（記録画面「その他」カードの遷移先）。開いたタブの**部位の種目だけ**を出す
/// （他部位への切替タブは置かない・ユーザー確定）。検索＋カスタム種目作成つき。
/// 選んだ/作った種目は onSelect で呼び出し側（タブのシェルフ）へ渡す。
/// 旧「種目を選んで追加する」フローの廃止で一時デッドコードだったが、
/// 2026-07 のタブフィルタ改修（シェルフへの追加導線）で復活した。
struct ExercisePickerView: View {
    /// 表示する種目（呼び出し側で同名重複を解決済みの一覧を渡す。部位はここで絞る）。
    let exercises: [Exercise]
    /// 開いているタブの部位。この部位の種目のみ表示し、新規作成の初期部位にもなる。
    let group: MuscleGroup
    var onSelect: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
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
            .navigationTitle("\(group.label)の種目を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            // 見つからなければその場で作成（部位はこのタブが初期値）→ 即選択（タブへ追加される）。
            .sheet(isPresented: $showAdd) {
                AddExerciseView(initialMuscleGroup: group, onCreated: { ex in
                    onSelect(ex)
                    dismiss()
                })
            }
        }
    }

    private var filtered: [Exercise] {
        exercises.filter { ex in
            ex.muscleGroup == group &&
            (search.isEmpty || ex.name.localizedCaseInsensitiveContains(search))
        }
    }
}
