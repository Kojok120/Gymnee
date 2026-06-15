import Foundation
import SwiftData

/// アプリ全体の SwiftData スキーマ定義（§4 全エンティティ）。
/// ModelContainer・Widget・テストから共通参照する単一の真実。
enum GymneeSchema {
    static let models: [any PersistentModel.Type] = [
        Profile.self,
        Gym.self,
        GymEquipment.self,
        Visit.self,
        VisitPartner.self,
        Workout.self,
        Exercise.self,
        WorkoutExercise.self,
        ExerciseSet.self,
        Routine.self,
        RoutineExercise.self,
        PersonalRecord.self,
        BodyMetric.self,
        ProgressPhoto.self,
        Follow.self,
        FeedItem.self,
        Product.self,
        Order.self,
        OrderItem.self,
        SupplyLog.self,
        Subscription.self,
    ]

    static let schema = Schema(models)

    /// アプリ本体用の永続コンテナ（オフラインファースト＝ローカルが正、§3/§7）。
    @MainActor
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            SeedData.seedIfNeeded(container.mainContext)
            return container
        } catch {
            // 旧スキーマ等で開けない場合はローカルストアを作り直す（v0 段階の割り切り）。
            assertionFailure("ModelContainer の生成に失敗: \(error)")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: fallback)
        }
    }

    /// テスト/プレビュー用のインメモリコンテナ。
    @MainActor
    static func makeInMemoryContainer(seeded: Bool = true) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: configuration)
        if seeded {
            SeedData.seedIfNeeded(container.mainContext)
        }
        return container
    }
}
