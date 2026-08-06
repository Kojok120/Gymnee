import Foundation
import OSLog
import SwiftData

/// スキーマ v1（§4 全エンティティ）。将来のモデル変更時は v2 を追加し、移行ステージを定義する。
enum GymneeSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            Profile.self,
            Workout.self,
            Exercise.self,
            WorkoutExercise.self,
            ExerciseSet.self,
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

    /// ストア退避が起きたことを UI に伝えるフラグ（RootView が一度だけアラートを出して消す）。
    static let recoveryPendingKey = "gymnee.storeRecoveryPending"

    private static let storeFileSuffixes = ["", "-wal", "-shm"]
    private static let log = Logger(subsystem: "com.gymnee.app", category: "persistence")

    /// アプリ本体用の永続コンテナ（オフラインファースト＝ローカルが正、§3/§7）。移行計画つき。
    ///
    /// 開けない（移行失敗・破損）場合の方針は構成で分ける：
    /// - DEBUG: ストアを消して作り直す（開発効率優先・[[gymnee-dev-db-wipe-ok]]）。
    /// - RELEASE: **消さない**。ローカルが正のため、未同期の記録が入ったストアの削除は
    ///   ユーザーデータの永久喪失になる。ストア一式を退避（移動）してから新規作成し、
    ///   退避分はサポート経由で復旧し得る状態を残す。
    @MainActor
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, migrationPlan: GymneeMigrationPlan.self, configurations: configuration)
            SeedData.seedIfNeeded(container.mainContext)
            return container
        } catch {
            log.error("ストアを開けない: \(error, privacy: .public)")
            #if DEBUG
            for suffix in storeFileSuffixes {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: configuration.url.path + suffix))
            }
            #else
            backupStoreFiles(at: configuration.url)
            UserDefaults.standard.set(true, forKey: recoveryPendingKey)
            #endif
            // 退避（移動）に失敗して旧ストアが残っている場合はここも失敗し、
            // 下のインメモリへ落ちる＝ディスク上のデータには触れない。
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

    /// 開けなくなったストア一式（base / -wal / -shm）を日時付きディレクトリへ**移動**する。
    /// 削除はしない。戻り値は退避先（何も移動しなかった場合は nil）。
    @discardableResult
    static func backupStoreFiles(at storeURL: URL, now: Date = .now) -> URL? {
        let fm = FileManager.default
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        let dir = storeURL.deletingLastPathComponent()
            .appendingPathComponent("StoreBackups", isDirectory: true)
            .appendingPathComponent(fmt.string(from: now), isDirectory: true)
        var moved = false
        for suffix in storeFileSuffixes {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            if !moved {
                do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
                    log.error("退避先を作成できない: \(error, privacy: .public)")
                    return nil
                }
            }
            do {
                try fm.moveItem(at: src, to: dir.appendingPathComponent(src.lastPathComponent))
                moved = true
            } catch {
                // 一部でも移動に失敗したら残りは触らない（中途半端に散らすより残す方が安全）。
                log.error("ストアの退避に失敗: \(error, privacy: .public)")
                return moved ? dir : nil
            }
        }
        return moved ? dir : nil
    }
}
