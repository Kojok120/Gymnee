import SwiftUI
import SwiftData

/// ジム自己登録（§6.4）。現在地を任意で取り込み、近隣候補表示に活用する。
struct AddGymView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @Environment(LocalSyncEngine.self) private var sync

    @State private var name = ""
    @State private var chain = ""
    @State private var captureLocation = true

    var body: some View {
        NavigationStack {
            Form {
                Section("ジム名") {
                    TextField("例: エニタイム◯◯店", text: $name)
                }
                Section("チェーン（任意）") {
                    TextField("例: Anytime Fitness", text: $chain)
                }
                Section {
                    Toggle("現在地を登録する", isOn: $captureLocation)
                    if captureLocation {
                        if let loc = location.current {
                            LabeledContent("現在地") {
                                Text(String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("位置情報を取得中… 許諾が必要です。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("現在地を登録すると、次回チェックイン時に近くのジムとして自動提案されます。")
                }
            }
            .navigationTitle("ジムを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if captureLocation { location.requestWhenInUse() }
            }
        }
    }

    private func save() {
        let loc = captureLocation ? location.current : nil
        let gym = Gym(
            name: name.trimmingCharacters(in: .whitespaces),
            chain: chain.isEmpty ? nil : chain,
            lat: loc?.coordinate.latitude,
            lng: loc?.coordinate.longitude,
            source: .user,
            createdBy: userId
        )
        context.insert(gym)
        try? context.save()
        sync.enqueue(PendingChange(entity: "gyms", recordId: gym.id, operation: .upsert, updatedAt: gym.updatedAt))
        dismiss()
    }
}
