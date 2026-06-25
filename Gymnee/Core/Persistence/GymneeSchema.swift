import Foundation
import SwiftData

/// スキーマ v1（§4 全エンティティ）。将来のモデル変更時は v2 を追加し、移行ステージを定義する。
enum GymneeSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
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
            Block.self,
            Report.self,
            FeedItem.self,
            PostReaction.self,
            Comment.self,
            PlannedWorkout.self,
            Product.self,
            SupplyLog.self,
            Subscription.self,
        ]
    }
}

/// 段階的マイグレーション計画（§7 データ保護）。
/// v1 のみのため stages は空。スキーマ変更時はここに MigrationStage を追加する。
enum GymneeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [GymneeSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// ModelContainer・Widget・テストから共通参照する単一の真実。
enum GymneeSchema {
    static let models = GymneeSchemaV1.models
    static let schema = Schema(versionedSchema: GymneeSchemaV1.self)

    /// アプリ本体用の永続コンテナ（オフラインファースト＝ローカルが正、§3/§7）。移行計画つき。
    @MainActor
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, migrationPlan: GymneeMigrationPlan.self, configurations: configuration)
            SeedData.seedIfNeeded(container.mainContext)
            return container
        } catch {
            // DEV 方針（[[gymnee-dev-db-wipe-ok]]）：移行不能ならストアを作り直す（既存データは破棄してよい）。
            // リリース前は効率優先で、スキーマ変更のたびに移行を作らない。本番公開時はこの方針を見直す。
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: configuration.url.path + suffix))
            }
            if let fresh = try? ModelContainer(for: schema, migrationPlan: GymneeMigrationPlan.self, configurations: configuration) {
                SeedData.seedIfNeeded(fresh.mainContext)
                return fresh
            }
            // それでも駄目ならインメモリで起動継続。
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
