import SwiftUI
import SwiftData

/// 身体メトリクスの手動入力（§6.7）。体重・体脂肪・各部位サイズ。
struct AddBodyMetricView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var health
    @Environment(LocalSyncEngine.self) private var sync

    @State private var date = Date.now
    @State private var weight: Double?
    @State private var bodyFat: Double?
    @State private var measurements: [String: Double] = [:]
    @State private var syncToHealth = true

    private let parts: [(key: String, label: String)] = [
        ("chest", "胸囲"), ("waist", "ウエスト"), ("arm", "腕"), ("thigh", "腿"), ("hip", "ヒップ"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("日付") { DatePicker("日付", selection: $date, displayedComponents: .date) }
                Section("基本") {
                    LabeledContent("体重") {
                        TextField("kg", value: $weight, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("体脂肪率") {
                        TextField("%", value: $bodyFat, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                Section("各部位サイズ (cm)") {
                    ForEach(parts, id: \.key) { part in
                        LabeledContent(part.label) {
                            TextField("cm", value: bindingFor(part.key), format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    }
                }
                if health.isAvailable {
                    Section {
                        Toggle("ヘルスケアにも書き込む", isOn: $syncToHealth)
                    }
                }
            }
            .navigationTitle("身体メトリクス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { Task { await save() } }
                        .disabled(weight == nil && bodyFat == nil && measurements.isEmpty)
                }
            }
        }
    }

    private func bindingFor(_ key: String) -> Binding<Double?> {
        Binding(
            get: { measurements[key] },
            set: { newValue in
                if let newValue { measurements[key] = newValue } else { measurements.removeValue(forKey: key) }
            }
        )
    }

    private func save() async {
        let metric = BodyMetric(userId: userId, date: date, weight: weight, bodyFat: bodyFat, measurements: measurements)
        context.insert(metric)
        try? context.save()
        sync.enqueue(PendingChange(entity: "body_metrics", recordId: metric.id, operation: .upsert, updatedAt: metric.updatedAt))
        if syncToHealth, let weight {
            await health.requestAuthorization()
            await health.saveBodyMass(weight, date: date)
        }
        dismiss()
    }
}
