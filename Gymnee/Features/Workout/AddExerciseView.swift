import SwiftUI
import SwiftData

/// カスタム種目作成（§6.5 種目マスタはプリセット＋ユーザー作成）。
struct AddExerciseView: View {
    /// 作成した種目を呼び出し側（ワークアウト/ルーティン）へ渡す。nil ならマスタ作成のみ。
    var onCreated: ((Exercise) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync

    @State private var name = ""
    @State private var muscleGroup: MuscleGroup = .chest
    @State private var equipment: EquipmentType = .barbell
    @State private var measurementType: MeasurementType = .weight
    @State private var weightMode: WeightMode = .both

    var body: some View {
        NavigationStack {
            Form {
                Section("種目名") {
                    TextField("例: ランドマインプレス", text: $name)
                }
                Section("部位") {
                    Picker("部位", selection: $muscleGroup) {
                        ForEach(MuscleGroup.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                equipmentSection
                typeSection
                if measurementType == .weight { weightModeSection }
            }
            .navigationTitle("カスタム種目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var equipmentSection: some View {
        Section("器具") {
            Picker("器具", selection: $equipment) {
                ForEach(EquipmentType.allCases, id: \.self) { (e: EquipmentType) in
                    Text(e.label).tag(e)
                }
            }
            .onChange(of: equipment) { _, eq in
                weightMode = Self.defaultWeightMode(for: eq)
            }
        }
    }

    /// 既定の片側/両側を器具から推定（ダンベル/ケトルベル＝片側）。
    private static func defaultWeightMode(for eq: EquipmentType) -> WeightMode {
        (eq == .dumbbell || eq == .kettlebell) ? .perSide : .both
    }

    private var typeSection: some View {
        Section("計測タイプ") {
            Picker("計測タイプ", selection: $measurementType) {
                ForEach(MeasurementType.allCases, id: \.self) { (t: MeasurementType) in
                    Text(t.label).tag(t)
                }
            }
            Text("ウェイト＝重量×回数 / 自重＝加重×回数 / 時間＝秒。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var weightModeSection: some View {
        Section("重量の数え方") {
            Picker("重量の数え方", selection: $weightMode) {
                ForEach(WeightMode.allCases, id: \.self) { (m: WeightMode) in
                    Text(m.label).tag(m)
                }
            }
        }
    }

    private func save() {
        let exercise = Exercise(
            name: name.trimmingCharacters(in: .whitespaces),
            muscleGroup: muscleGroup,
            equipment: equipment,
            isCustom: true,
            createdBy: auth.currentUserId,
            weightMode: weightMode,
            measurementType: measurementType
        )
        context.insert(exercise)
        // 保存に成功した時だけ enqueue / onCreated へ進む（未保存の種目を呼び出し側へ渡さない）。
        do { try context.save() } catch { return }
        sync.enqueue(PendingChange(entity: "exercises", recordId: exercise.id, operation: .upsert, updatedAt: exercise.updatedAt))
        onCreated?(exercise)
        dismiss()
    }
}
