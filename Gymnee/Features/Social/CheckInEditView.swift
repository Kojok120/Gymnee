import SwiftUI
import SwiftData

/// チェックイン（来店）の編集（§6.11）。メモ・来店日時・公開範囲を後から変更できる。
struct CheckInEditView: View {
    @Bindable var visit: Visit
    let visibilityStore: PostVisibilityStore

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalSyncEngine.self) private var sync
    @State private var visibility: Visibility

    init(visit: Visit, visibilityStore: PostVisibilityStore) {
        self.visit = visit
        self.visibilityStore = visibilityStore
        let fallback = Visibility(rawValue: UserDefaults.standard.string(forKey: "gymnee.defaultVisibility") ?? "") ?? .public
        _visibility = State(initialValue: visibilityStore.visibility(for: visit.id) ?? fallback)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("ジム") {
                    Label(visit.gym?.name ?? "ジム", systemImage: "building.2.fill")
                }
                Section("日時") {
                    DatePicker("来店日時", selection: $visit.visitedAt)
                }
                Section("メモ") {
                    TextField("今日の調子・メニューなど", text: noteBinding, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Picker("公開範囲", selection: $visibility) {
                        ForEach(Visibility.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("公開範囲")
                } footer: {
                    Text("この投稿を誰に見せるか。既定値は設定で変更できます。")
                }
            }
            .navigationTitle("チェックインを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("保存") { save() }.bold() }
            }
        }
    }

    private var noteBinding: Binding<String> {
        Binding(get: { visit.note ?? "" }, set: { visit.note = $0.isEmpty ? nil : $0 })
    }

    private func save() {
        visit.updatedAt = .now
        visit.isDirty = true
        try? context.save()
        sync.enqueue(PendingChange(entity: "visits", recordId: visit.id, operation: .upsert, updatedAt: visit.updatedAt))
        visibilityStore.set(visibility, for: visit.id)
        dismiss()
    }
}
