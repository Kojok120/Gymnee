import SwiftUI

/// セット入力 1 行（§6.5）。種別・重量・レップ・RPE・完了・PR バッジ。
struct SetRowView: View {
    @Bindable var set: ExerciseSet
    var onComplete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            typeButton

            numberField(value: $set.weight, width: 64, suffix: "kg")
            Text("×").foregroundStyle(.secondary)
            intField(value: $set.reps, width: 48)

            rpeField

            Spacer(minLength: 0)

            if set.isPR {
                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
            }

            doneButton
        }
        .font(.subheadline)
    }

    private var typeButton: some View {
        Menu {
            ForEach(SetType.allCases, id: \.self) { t in
                Button(t.label) { set.type = t; set.updatedAt = .now }
            }
        } label: {
            Text(typeBadge)
                .font(.caption2.bold())
                .frame(width: 28, height: 28)
                .background(typeColor.opacity(0.2), in: Circle())
                .foregroundStyle(typeColor)
        }
    }

    private var rpeField: some View {
        TextField("RPE", value: $set.rpe, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .frame(width: 44)
            .foregroundStyle(.secondary)
            .font(.caption)
    }

    private var doneButton: some View {
        Button {
            set.isCompleted.toggle()
            set.updatedAt = .now
            if set.isCompleted { onComplete() }
        } label: {
            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(set.isCompleted ? Theme.energy : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func numberField(value: Binding<Double>, width: CGFloat, suffix: String) -> some View {
        HStack(spacing: 1) {
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: width)
            Text(suffix).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func intField(value: Binding<Int>, width: CGFloat) -> some View {
        TextField("0", value: value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .frame(width: width)
    }

    private var typeBadge: String {
        switch set.type {
        case .normal: return "\(set.setIndex + 1)"
        case .warmup: return "W"
        case .drop: return "D"
        case .superset: return "S"
        }
    }

    private var typeColor: Color {
        switch set.type {
        case .normal: return Theme.energy
        case .warmup: return .orange
        case .drop: return .purple
        case .superset: return .blue
        }
    }
}
