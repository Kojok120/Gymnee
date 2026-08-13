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

/// スキーマ v2。育成タブの遠征記録（ローカル専用の `ExpeditionRun`）を追加しただけの
/// 純粋な追加変更のため、移行は lightweight で足りる（既存エンティティは無改変）。
enum GymneeSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        GymneeSchemaV1.models + [ExpeditionRun.self]
    }
}

/// スキーマ v3。キャラの見た目（装備とスキン）の保存先 `CharacterLoadout` を追加。
/// これも純粋な追加変更のため lightweight で足りる。
enum GymneeSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        GymneeSchemaV2.models + [CharacterLoadout.self]
    }
}

/// スキーマ v4。AI コーチとの会話 `CoachMessage` を追加。
/// これも純粋な追加変更のため lightweight で足りる。
enum GymneeSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        GymneeSchemaV3.models + [CoachMessage.self]
    }
}

/// スキーマ v5。部屋に落ちているグッズを拾った記録 `RoomPickupRecord` を追加。
/// これも純粋な追加変更のため lightweight で足りる。
enum GymneeSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        GymneeSchemaV4.models + [RoomPickupRecord.self]
    }
}

/// スキーマ v6。髪型・アクセサリーの `CharacterStyle` を追加。
///
/// **既存モデルへのプロパティ追加ではなく、必ず「型の追加」で表現すること。**
/// モデル型の一覧が前バージョンと同じだとチェックサムが衝突して
/// 「Duplicate version checksums detected.」で落ち、かといってバージョンを据え置くと
/// 「Cannot use staged migration with an unknown model version」でストアが開けず、
/// 退避＝ユーザーのローカルデータ消失につながる（実際に起こした）。
enum GymneeSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] {
        GymneeSchemaV5.models + [CharacterStyle.self]
    }
}

/// スキーマ v7。差分 pull の基準時刻 `SyncWatermark` を追加。
///
/// 基準時刻を UserDefaults からストアの中へ移すための追加。
/// ストアが作り直されたら基準も一緒に消える＝次回が自動でフル取得になる（`SyncWatermark` 参照）。
enum GymneeSchemaV7: VersionedSchema {
    static var versionIdentifier = Schema.Version(7, 0, 0)
    static var models: [any PersistentModel.Type] {
        GymneeSchemaV6.models + [SyncWatermark.self]
    }
}

/// スキーマ v8。連れているペット `PetState` を追加。
///
/// v6 と同じく**型の追加**で表現する。既存モデルへのプロパティ追加はチェックサム衝突を起こし、
/// 実際にローカルデータ消失の事故になった（`CharacterStyle` のコメント参照）。
enum GymneeSchemaV8: VersionedSchema {
    static var versionIdentifier = Schema.Version(8, 0, 0)
    static var models: [any PersistentModel.Type] {
        GymneeSchemaV7.models + [PetState.self]
    }
}

/// 段階的マイグレーション計画（§7 データ保護）。
/// スキーマ変更時はここに MigrationStage を追加する。
enum GymneeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [GymneeSchemaV1.self, GymneeSchemaV2.self, GymneeSchemaV3.self, GymneeSchemaV4.self, GymneeSchemaV5.self, GymneeSchemaV6.self, GymneeSchemaV7.self, GymneeSchemaV8.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: GymneeSchemaV1.self, toVersion: GymneeSchemaV2.self),
            .lightweight(fromVersion: GymneeSchemaV2.self, toVersion: GymneeSchemaV3.self),
            .lightweight(fromVersion: GymneeSchemaV3.self, toVersion: GymneeSchemaV4.self),
            .lightweight(fromVersion: GymneeSchemaV4.self, toVersion: GymneeSchemaV5.self),
            .lightweight(fromVersion: GymneeSchemaV5.self, toVersion: GymneeSchemaV6.self),
            .lightweight(fromVersion: GymneeSchemaV6.self, toVersion: GymneeSchemaV7.self),
            .lightweight(fromVersion: GymneeSchemaV7.self, toVersion: GymneeSchemaV8.self),
        ]
    }
}

/// ModelContainer・Widget・テストから共通参照する単一の真実。
enum GymneeSchema {
    static let models = GymneeSchemaV8.models
    static let schema = Schema(versionedSchema: GymneeSchemaV8.self)

    /// ストア退避が起きたことを UI に伝えるフラグ（RootView が一度だけアラートを出して消す）。
    static let recoveryPendingKey = "gymnee.storeRecoveryPending"

    /// 旧実装（UserDefaults に基準時刻を置いていた頃）の残骸を掃除する。
    /// 現在の基準時刻は `SyncWatermark` としてストアの中にあり、ストアと生死を共にする。
    static func purgeLegacyWatermarkDefaults() {
        SyncRecovery.purgeLegacyWatermarks()
        log.info("旧実装の差分基準（UserDefaults）を掃除した")
    }

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
            // 差分同期の基準時刻（`SyncWatermark`）はストアの中にあるので、
            // ストアを作り直せば自動的に消えて次回がフル取得になる。
            // 旧実装で UserDefaults に残っている分だけここで掃除する。
            purgeLegacyWatermarkDefaults()
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
