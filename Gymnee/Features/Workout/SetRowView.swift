import SwiftUI
import UIKit

/// 数値入力フィールド。値が 0 のときは空表示（プレースホルダのみ）、フォーカス時に全選択して
/// 既存値を即上書きできるようにする（「毎回 0 を消す」手間をなくす）。小数入力中の再フォーマット
/// 問題を避けるため、編集中は UITextField のテキストを正とし、確定値だけモデルへ書き戻す。
struct NumberField: UIViewRepresentable {
    let placeholder: String
    let keyboard: UIKeyboardType
    var color: Color = Theme.textPrimary
    let get: () -> String
    let set: (String) -> Void

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.keyboardType = keyboard
        tf.textAlignment = .center
        tf.placeholder = placeholder
        tf.delegate = context.coordinator
        let base = UIFont.systemFont(ofSize: 19, weight: .semibold)
        tf.font = UIFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 19)
        tf.setContentHuggingPriority(.required, for: .horizontal)
        // 点滅キャレットをはっきり見せる（入力箇所が分かるように）。
        tf.tintColor = UIColor(Theme.energy)
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        tf.textColor = UIColor(color)
        // 編集中はユーザー入力（小数入力途中など）を尊重し、上書きしない。
        if !tf.isFirstResponder { tf.text = get() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(set: set) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let set: (String) -> Void
        init(set: @escaping (String) -> Void) { self.set = set }
        @objc func editingChanged(_ tf: UITextField) { set(tf.text ?? "") }
        // selectAll はせず点滅キャレットを表示する。値が 0 のときは空表示なので、
        // 新規セットはタップ→そのまま入力できる（0 を消す手間はないまま）。
    }
}

/// 末尾の .0 を落とした表示（50.0→"50"、52.5→"52.5"）。
private func numberString(_ value: Double) -> String {
    if value == 0 { return "" }
    return value == value.rounded() ? String(Int(value)) : String(value)
}

/// セット入力 1 行（§6.5）。種別・重量・レップ・RPE・完了・PR バッジ。
/// 大きな丸数字 + 広いタップ領域。完了で lime に染まり、PR でメダルが弾ける。
struct SetRowView: View {
    @Bindable var set: ExerciseSet
    var onComplete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            typeButton

            field(value: $set.weight, suffix: "kg", width: 58)
            weightModeBadge
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
        // 固定幅の数値入力が特大文字で潰れて完了ボタンが押せなくなるのを防ぐため上限を設定。
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(.bouncy, value: set.isPR)
        .animation(.snappy, value: set.isCompleted)
    }

    /// 重量の数え方バッジ（両/片）。タップで「種目に従う／両側／片側」を選べる。上書き時は lime。
    private var weightModeBadge: some View {
        Menu {
            Button("種目に従う") { set.weightModeOverride = nil; set.updatedAt = .now; set.isDirty = true }
            ForEach(WeightMode.allCases, id: \.self) { m in
                Button(m.label) { set.weightModeOverride = m; set.updatedAt = .now; set.isDirty = true }
            }
        } label: {
            Text(set.effectiveWeightMode.short)
                .font(.caption2.bold())
                .foregroundStyle(set.weightModeOverride == nil ? Theme.textTertiary : Theme.onLime)
                .frame(width: 20, height: 20)
                .background((set.weightModeOverride == nil ? Theme.textTertiary.opacity(0.12) : Theme.lime), in: Circle())
        }
        .buttonStyle(.plain)
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
            NumberField(
                placeholder: "0",
                keyboard: .decimalPad,
                color: set.isCompleted ? Theme.lime : Theme.textPrimary,
                get: { numberString(value.wrappedValue) },
                set: {
                    value.wrappedValue = Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0
                    set.updatedAt = .now
                }
            )
            .frame(width: width)
            Text(suffix).font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    private func intField(value: Binding<Int>, width: CGFloat) -> some View {
        NumberField(
            placeholder: "0",
            keyboard: .numberPad,
            color: set.isCompleted ? Theme.lime : Theme.textPrimary,
            get: { value.wrappedValue == 0 ? "" : String(value.wrappedValue) },
            set: {
                value.wrappedValue = Int($0) ?? 0
                set.updatedAt = .now
            }
        )
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
