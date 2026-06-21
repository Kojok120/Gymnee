import SwiftUI

/// セット入力 1 行（§6.5）。種別・重量・レップ・RPE・完了・PR バッジ。
/// 大きな丸数字 + 広いタップ領域。完了で lime に染まり、PR でメダルが弾ける。
struct SetRowView: View {
    @Bindable var set: ExerciseSet
    var onComplete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            typeButton

            field(value: $set.weight, suffix: "kg", width: 58)
            Text("×").font(.headline).foregroundStyle(Theme.textTertiary)
            intField(value: $set.reps, width: 40)

            rpeField

            Spacer(minLength: 0)

            if set.isPR {
                Image(systemName: "medal.fill")
                    .font(.body)
                    .foregroundStyle(Theme.lime)
                    .transition(.scale.combined(with: .opacity))
            }

            doneButton
        }
        .padding(.vertical, 2)
        .animation(.bouncy, value: set.isPR)
        .animation(.snappy, value: set.isCompleted)
    }

    private var typeButton: some View {
        Menu {
            ForEach(SetType.allCases, id: \.self) { t in
                Button(t.label) { set.type = t; set.updatedAt = .now }
            }
        } label: {
            Text(typeBadge)
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 30, height: 30)
                .background(typeColor.opacity(0.18), in: Circle())
                .foregroundStyle(typeColor)
        }
    }

    private var rpeField: some View {
        TextField("RPE", value: $set.rpe, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .frame(width: 40)
            .foregroundStyle(Theme.textSecondary)
            .font(.caption)
    }

    private var doneButton: some View {
        Button {
            set.isCompleted.toggle()
            set.updatedAt = .now
            if set.isCompleted { onComplete() }
        } label: {
            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(set.isCompleted ? Theme.lime : Theme.textTertiary)
                .symbolEffect(.bounce, value: set.isCompleted)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: set.isCompleted)
    }

    private func field(value: Binding<Double>, suffix: String, width: CGFloat) -> some View {
        HStack(spacing: 2) {
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.numS)
                .foregroundStyle(set.isCompleted ? Theme.lime : Theme.textPrimary)
                .frame(width: width)
            Text(suffix).font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    private func intField(value: Binding<Int>, width: CGFloat) -> some View {
        TextField("0", value: value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.numS)
            .foregroundStyle(set.isCompleted ? Theme.lime : Theme.textPrimary)
            .frame(width: width)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    private var fieldBackground: Color {
        return set.isCompleted ? Theme.limeSoft : Theme.bg2
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
        case .normal: return Theme.lime
        case .warmup: return Theme.warning
        case .drop: return Theme.series2
        case .superset: return Theme.info
        }
    }
}
