import SwiftUI
import SwiftData

/// 身体メトリクスの手動入力（§6.7）。身長・体重・体脂肪率の3項目に絞る。
/// 身長は measurements["height"]（cm）に保持し、モデル/サーバ列は増やさない。
struct AddBodyMetricView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var health
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(AppErrorCenter.self) private var errors

    @State private var date = Date.now
    @State private var weight: Double?
    @State private var bodyFat: Double?
    @State private var measurements: [String: Double] = [:]
    @State private var syncToHealth = true

    var body: some View {
        NavigationStack {
            Form {
                Section("日付") { DatePicker("日付", selection: $date, displayedComponents: .date) }
                Section("基本") {
                    LabeledContent("身長") {
                        TextField("cm", value: bindingFor("height"), format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("体重") {
                        TextField("kg", value: $weight, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("体脂肪率") {
                        TextField("%", value: $bodyFat, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
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
        do {
            try context.save()
        } catch {
            errors.report("記録を保存できませんでした。\(error.localizedDescription)")
            return
        }
        sync.enqueue(PendingChange(entity: "body_metrics", recordId: metric.id, operation: .upsert, updatedAt: metric.updatedAt))
        if syncToHealth, let weight {
            await health.requestAuthorization()
            await health.saveBodyMass(weight, date: date)
        }
        dismiss()
    }
}
