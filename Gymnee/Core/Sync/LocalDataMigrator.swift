import Foundation
import SwiftData

/// ローカル先行で作ったデータを、Supabase サインイン後の本物の userId に付け替える。
/// これが無いと、サインイン前にローカル ID で作った記録は user_id が auth.uid と一致せず
/// RLS で弾かれ、永遠に同期されない。
@MainActor
enum LocalDataMigrator {
    /// `from`（旧ローカル userId）の所有データを `to`（Supabase userId）へ付け替え、再送出キューに積む。
    static func reassign(from old: UUID, to new: UUID, context: ModelContext, sync: LocalSyncEngine) {
        guard old != new else { return }
        var pending: [PendingChange] = []  // 変更を集めて最後に一括 enqueue（ディスク書込1回）。

        // 所有者(user_id)を持つルート。
        reassignOwned(Visit.self, entity: "visits", context: context, into: &pending) { $0.userId == old } set: { $0.userId = new }
        reassignOwned(Workout.self, entity: "workouts", context: context, into: &pending) { $0.userId == old } set: { $0.userId = new }
        reassignOwned(Routine.self, entity: "routines", context: context, into: &pending) { $0.userId == old } set: { $0.userId = new }
        reassignOwned(PersonalRecord.self, entity: "personal_records", context: context, into: &pending) { $0.userId == old } set: { $0.userId = new }
        reassignOwned(BodyMetric.self, entity: "body_metrics", context: context, into: &pending) { $0.userId == old } set: { $0.userId = new }
        reassignOwned(ProgressPhoto.self, entity: "progress_photos", context: context, into: &pending) { $0.userId == old } set: { $0.userId = new }
        reassignOwned(SupplyLog.self, entity: "supply_logs", context: context, into: &pending) { $0.userId == old } set: { $0.userId = new }
        reassignOwned(Subscription.self, entity: "subscriptions", context: context, into: &pending) { $0.userId == old } set: { $0.userId = new }
        reassignOwned(FeedItem.self, entity: "feed_items", context: context, into: &pending) { $0.userId == old } set: { $0.userId = new }
        reassignOwned(PostReaction.self, entity: "post_reactions", context: context, into: &pending) { $0.userId == old } set: { $0.userId = new }
        // フォローは follower 側を付け替え。
        reassignOwned(Follow.self, entity: "follows", context: context, into: &pending) { $0.followerId == old } set: { $0.followerId = new }
        // ブロック/通報は実行者(blocker / reporter)側を付け替え。
        reassignOwned(Block.self, entity: "blocks", context: context, into: &pending) { $0.blockerId == old } set: { $0.blockerId = new }
        reassignOwned(Report.self, entity: "reports", context: context, into: &pending) { $0.reporterId == old } set: { $0.reporterId = new }
        // マスタはユーザー作成分(created_by)のみ。
        reassignOwned(Gym.self, entity: "gyms", context: context, into: &pending) { $0.createdBy == old } set: { $0.createdBy = new }
        reassignOwned(Exercise.self, entity: "exercises", context: context, into: &pending) { $0.createdBy == old } set: { $0.createdBy = new }

        // 子テーブルは所有者列を持たない（親の user_id で RLS 判定）が、親の付け替えで
        // 通るようになるため再送出キューに積む。
        reenqueueAll(VisitPartner.self, entity: "visit_partners", context: context, into: &pending)
        reenqueueAll(WorkoutExercise.self, entity: "workout_exercises", context: context, into: &pending)
        reenqueueAll(ExerciseSet.self, entity: "exercise_sets", context: context, into: &pending)
        reenqueueAll(RoutineExercise.self, entity: "routine_exercises", context: context, into: &pending)
        reenqueueAll(GymEquipment.self, entity: "gym_equipment", context: context, into: &pending)

        // 旧 userId のローカル Profile は孤児になるため削除（新 Profile は ensureProfile / トリガで存在）。
        if let oldProfile = try? context.fetch(FetchDescriptor<Profile>(predicate: #Predicate { $0.id == old })).first {
            context.delete(oldProfile)
        }
        try? context.save()
        sync.enqueueBatch(pending)  // ディスク書込・自動同期は 1 回だけ。
    }

    private static func reassignOwned<T: PersistentModel>(
        _ type: T.Type,
        entity: String,
        context: ModelContext,
        into pending: inout [PendingChange],
        match: (T) -> Bool,
        set: (T) -> Void
    ) {
        guard let all = try? context.fetch(FetchDescriptor<T>()) else { return }
        for model in all where match(model) {
            set(model)
            if let change = touched(model, entity: entity) { pending.append(change) }
        }
    }

    private static func reenqueueAll<T: PersistentModel>(
        _ type: T.Type,
        entity: String,
        context: ModelContext,
        into pending: inout [PendingChange]
    ) {
        guard let all = try? context.fetch(FetchDescriptor<T>()) else { return }
        for model in all {
            if let change = touched(model, entity: entity) { pending.append(change) }
        }
    }

    /// updatedAt/isDirty を更新し、送出用の変更を返す（モデルは id/updatedAt/isDirty を持つ前提）。
    private static func touched<T: PersistentModel>(_ model: T, entity: String) -> PendingChange? {
        guard let id = (model as? any SyncIdentifiable)?.syncId else { return nil }
        (model as? any SyncIdentifiable)?.markDirty()
        return PendingChange(entity: entity, recordId: id, operation: .upsert, updatedAt: .now)
    }
}

/// 付け替え対象モデルが共通で持つ id / updatedAt / isDirty へアクセスするための内部プロトコル。
protocol SyncIdentifiable {
    var syncId: UUID { get }
    func markDirty()
}

// 各モデルの conformance（id / updatedAt / isDirty を持つ前提。モデル定義は変更しない）。
extension Visit: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension Workout: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension Routine: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension PersonalRecord: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension BodyMetric: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension ProgressPhoto: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension SupplyLog: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension Subscription: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension FeedItem: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension Follow: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension Gym: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension Exercise: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension VisitPartner: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension WorkoutExercise: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension ExerciseSet: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension RoutineExercise: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
extension GymEquipment: SyncIdentifiable { var syncId: UUID { id }; func markDirty() { updatedAt = .now; isDirty = true } }
