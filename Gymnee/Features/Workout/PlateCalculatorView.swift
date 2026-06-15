import SwiftUI

/// プレート計算機（§6.5）。目標重量に対する片側プレート構成を提示。
struct PlateCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var target: Double
    @State private var bar: Double = 20

    init(initialTarget: Double = 60) {
        _target = State(initialValue: max(initialTarget, 20))
    }

    private var result: PlateCalculator.Result {
        PlateCalculator.compute(target: target, bar: bar)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("設定") {
                    Stepper(value: $target, in: 20...500, step: 2.5) {
                        LabeledContent("目標重量", value: String(format: "%.1f kg", target))
                    }
                    Picker("バー重量", selection: $bar) {
                        Text("20kg").tag(20.0)
                        Text("15kg").tag(15.0)
                        Text("10kg").tag(10.0)
                    }
                }

                Section("片側のプレート") {
                    if result.perSide.isEmpty {
                        Text(target <= bar ? "バーのみ（プレート不要）" : "計算できません")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(result.perSide) { pc in
                            HStack {
                                plateChip(pc.plate)
                                Text(String(format: "%.4g kg", pc.plate))
                                Spacer()
                                Text("× \(pc.count)").bold()
                            }
                        }
                    }
                    if !result.isExact && target > bar {
                        Text(String(format: "片側 %.2fkg 足りません（最小プレート不足）", result.remainderPerSide))
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Section {
                    barbellVisual
                }
            }
            .navigationTitle("プレート計算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } }
            }
        }
    }

    private func plateChip(_ weight: Double) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.energy)
            .frame(width: 10, height: max(16, min(40, weight)))
    }

    private var barbellVisual: some View {
        HStack(spacing: 2) {
            ForEach(Array(result.perSide.flatMap { pc in Array(repeating: pc.plate, count: pc.count) }.enumerated()), id: \.offset) { _, w in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.energy)
                    .frame(width: 8, height: max(20, min(56, w * 1.6)))
            }
            Rectangle().fill(Color.secondary).frame(height: 6)
        }
        .frame(height: 60)
    }
}
