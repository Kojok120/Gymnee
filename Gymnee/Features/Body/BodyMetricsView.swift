import SwiftUI
import SwiftData
import Charts

/// 身体メトリクス（§6.7）。体重・体脂肪・各部位サイズの記録と推移。HealthKit と双方向。
struct BodyMetricsView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(HealthKitService.self) private var health
    @Environment(LocalSyncEngine.self) private var sync
    @Query private var metrics: [BodyMetric]
    @State private var showAdd = false
    @State private var importing = false

    init(userId: UUID) {
        self.userId = userId
        _metrics = Query(
            filter: #Predicate<BodyMetric> { $0.userId == userId },
            sort: \BodyMetric.date, order: .reverse
        )
    }

    var body: some View {
        List {
            if metrics.contains(where: { $0.weight != nil }) {
                Section("体重推移") {
                    weightChart.frame(height: 200)
                }
            }
            Section {
                ForEach(metrics) { m in
                    HStack {
                        Text(m.date, format: .dateTime.year().month().day())
                        Spacer()
                        if let h = m.measurements["height"] { Text(String(format: "%.0fcm", h)).foregroundStyle(.secondary) }
                        if let w = m.weight { Text(String(format: "%.1fkg", w)) }
                        if let bf = m.bodyFat { Text(String(format: "%.1f%%", bf)).foregroundStyle(.secondary) }
                        if m.fromHealthKit { Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.pink) }
                    }
                }
                .onDelete(perform: delete)
            } header: {
                Text("記録")
            } footer: {
                if metrics.isEmpty { Text("右上の＋で身長・体重・体脂肪率を記録できます。") }
            }
        }
        .navigationTitle("身体メトリクス")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showAdd = true } label: { Label("手動で記録", systemImage: "square.and.pencil") }
                    Button { Task { await importFromHealth() } } label: { Label("ヘルスケアから取込", systemImage: "heart.fill") }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddBodyMetricView(userId: userId) }
        .overlay { if importing { ProgressView("取込中…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
    }

    private var weightChart: some View {
        Chart(metrics.filter { $0.weight != nil }.sorted { $0.date < $1.date }) { m in
            LineMark(x: .value("日付", m.date), y: .value("体重", m.weight ?? 0))
                .foregroundStyle(Theme.energy)
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("日付", m.date), y: .value("体重", m.weight ?? 0))
                .foregroundStyle(Theme.energy)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel("kg")
    }

    private func importFromHealth() async {
        importing = true
        defer { importing = false }
        await health.requestAuthorization()
        let weight = await health.latestBodyMass()
        let bodyFat = await health.latestBodyFat()
        guard weight != nil || bodyFat != nil else { return }
        let metric = BodyMetric(userId: userId, date: .now, weight: weight, bodyFat: bodyFat, fromHealthKit: true)
        context.insert(metric)
        try? context.save()
        sync.enqueue(PendingChange(entity: "body_metrics", recordId: metric.id, operation: .upsert, updatedAt: metric.updatedAt))
    }

    private func delete(_ offsets: IndexSet) {
        let removedIds = offsets.map { metrics[$0].id }
        for i in offsets { context.delete(metrics[i]) }
        try? context.save()
        for id in removedIds {
            sync.enqueue(PendingChange(entity: "body_metrics", recordId: id, operation: .delete, updatedAt: .now))
        }
    }
}
