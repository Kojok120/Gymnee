import Foundation
import SwiftData

/// SwiftData 行 ⇄ Supabase(PostgREST) JSON の変換実装（`SyncBackingStore`）。
/// - `payload(for:)`: outbox の 1 件（recordId）をモデルから snake_case の行 JSON へ符号化。
/// - `apply(table:rows:)`: 受信行を ConflictResolver（updated_at の LWW, §9-7）でローカルへ統合。
/// - `lastPulledAt`/`setLastPulledAt`: 差分 pull の基準時刻を UserDefaults に保持。
///
/// ⚠️ 実 Supabase での結合テスト（型・NULL・関係の往復）は M2 で行うこと。列名は `supabase/migrations` と一致。
@MainActor
final class SwiftDataSyncStore: SyncBackingStore {
    private let context: ModelContext
    private let defaults: UserDefaults

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
    }

    /// 同期中のバックエンド本人 id（AuthService が永続化）。RLS の created_by = auth.uid() 整合用。
    private var currentUserId: UUID? {
        defaults.string(forKey: "gymnee.supabase.userId").flatMap(UUID.init)
    }

    // MARK: - 差分基準

    func lastPulledAt(table: String) -> Date? {
        let t = defaults.double(forKey: key(table))
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    func setLastPulledAt(_ date: Date, table: String) {
        defaults.set(date.timeIntervalSince1970, forKey: key(table))
    }

    private func key(_ table: String) -> String { "gymnee.sync.lastPulled.\(table)" }

    // MARK: - 符号化（push）

    func payload(for change: PendingChange) -> [String: Any]? {
        guard change.operation == .upsert else { return nil } // delete は id だけで処理
        let id = change.recordId
        switch change.entity {
        case "profiles":          return fetchProfile(id).map(encodeProfile)
        case "gyms":              return fetchGym(id).map(encodeGym)
        case "gym_equipment":     return fetchGymEquipment(id).map(encodeGymEquipment)
        case "visits":            return fetchVisit(id).map(encodeVisit)
        case "visit_partners":    return fetchVisitPartner(id).map(encodeVisitPartner)
        case "workouts":          return fetchWorkout(id).map(encodeWorkout)
        case "exercises":         return fetchExercise(id).map(encodeExercise)
        case "workout_exercises": return fetchWorkoutExercise(id).map(encodeWorkoutExercise)
        case "exercise_sets":     return fetchExerciseSet(id).map(encodeExerciseSet)
        case "routines":          return fetchRoutine(id).map(encodeRoutine)
        case "routine_exercises": return fetchRoutineExercise(id).map(encodeRoutineExercise)
        case "personal_records":  return fetchPersonalRecord(id).map(encodePersonalRecord)
        case "body_metrics":      return fetchBodyMetric(id).map(encodeBodyMetric)
        case "progress_photos":   return fetchProgressPhoto(id).map(encodeProgressPhoto)
        case "follows":           return fetchFollow(id).map(encodeFollow)
        case "blocks":            return fetchBlock(id).map(encodeBlock)
        case "reports":           return fetchReport(id).map(encodeReport)
        case "feed_items":        return fetchFeedItem(id).map(encodeFeedItem)
        case "post_reactions":    return fetchPostReaction(id).map(encodePostReaction)
        case "supply_logs":       return fetchSupplyLog(id).map(encodeSupplyLog)
        case "subscriptions":     return fetchSubscription(id).map(encodeSubscription)
        // products はサーバ管理カタログ（クライアントから push しない）。
        default: return nil
        }
    }

    // MARK: - 復号（pull）

    func apply(table: String, rows: [[String: Any]]) {
        for row in rows {
            switch table {
            case "profiles":          applyProfile(row)
            case "gyms":              applyGym(row)
            case "gym_equipment":     applyGymEquipment(row)
            case "visits":            applyVisit(row)
            case "visit_partners":    applyVisitPartner(row)
            case "workouts":          applyWorkout(row)
            case "exercises":         applyExercise(row)
            case "workout_exercises": applyWorkoutExercise(row)
            case "exercise_sets":     applyExerciseSet(row)
            case "routines":          applyRoutine(row)
            case "routine_exercises": applyRoutineExercise(row)
            case "personal_records":  applyPersonalRecord(row)
            case "body_metrics":      applyBodyMetric(row)
            case "progress_photos":   applyProgressPhoto(row)
            case "follows":           applyFollow(row)
            case "blocks":            applyBlock(row)
            case "reports":           applyReport(row)
            case "feed_items":        applyFeedItem(row)
            case "post_reactions":    applyPostReaction(row)
            case "products":          applyProduct(row)
            case "supply_logs":       applySupplyLog(row)
            case "subscriptions":     applySubscription(row)
            default: break
            }
        }
        try? context.save()
    }

    /// 既存があり、ローカルの方が新しければ true（＝リモートを捨てる）。LWW（§9-7）。
    private func remoteIsStale(localUpdatedAt: Date?, _ row: [String: Any]) -> Bool {
        guard let localUpdatedAt else { return false }
        let remote = date(row["updated_at"]) ?? .distantPast
        return ConflictResolver.resolve(localUpdatedAt: localUpdatedAt, remoteUpdatedAt: remote) == .local
    }

    // MARK: - profiles
    private func encodeProfile(_ m: Profile) -> [String: Any] {
        ["id": lower(m.id), "display_name": m.displayName, "avatar_url": opt(m.avatarURL),
         "bio": opt(m.bio), "created_at": iso(m.createdAt), "updated_at": iso(m.updatedAt)]
    }
    private func applyProfile(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchProfile(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(Profile(id: id, displayName: str(row["display_name"]) ?? "ゲスト"))
        m.displayName = str(row["display_name"]) ?? m.displayName
        m.avatarURL = str(row["avatar_url"])
        m.bio = str(row["bio"])
        m.createdAt = date(row["created_at"]) ?? m.createdAt
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - gyms
    private func encodeGym(_ m: Gym) -> [String: Any] {
        var row: [String: Any] = [
            "id": lower(m.id), "name": m.name, "chain": opt(m.chain), "address": opt(m.address),
            "lat": opt(m.lat), "lng": opt(m.lng), "source": m.sourceRaw, "is_favorite": m.isFavorite,
            "created_at": iso(m.createdAt), "updated_at": iso(m.updatedAt),
        ]
        if let by = m.createdBy { row["created_by"] = lower(by) } // nil は DB 既定 auth.uid() に委ねる
        return row
    }
    private func applyGym(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchGym(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(Gym(id: id, name: str(row["name"]) ?? "ジム"))
        m.name = str(row["name"]) ?? m.name
        m.chain = str(row["chain"]); m.address = str(row["address"])
        m.lat = dbl(row["lat"]); m.lng = dbl(row["lng"])
        m.sourceRaw = str(row["source"]) ?? m.sourceRaw
        m.createdBy = uuid(row["created_by"])
        m.isFavorite = bool(row["is_favorite"]) ?? m.isFavorite
        m.createdAt = date(row["created_at"]) ?? m.createdAt
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - gym_equipment
    private func encodeGymEquipment(_ m: GymEquipment) -> [String: Any] {
        ["id": lower(m.id), "gym_id": opt(m.gym?.id.uuidString.lowercased()),
         "label": m.label, "note": opt(m.note), "updated_at": iso(m.updatedAt)]
        // created_by は DB 既定 auth.uid()。
    }
    private func applyGymEquipment(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchGymEquipment(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(GymEquipment(id: id, label: str(row["label"]) ?? ""))
        m.label = str(row["label"]) ?? m.label
        m.note = str(row["note"])
        m.gym = uuid(row["gym_id"]).flatMap(fetchGym)
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - visits
    private func encodeVisit(_ m: Visit) -> [String: Any] {
        ["id": lower(m.id), "user_id": lower(m.userId), "gym_id": opt(m.gym?.id.uuidString.lowercased()),
         "visited_at": iso(m.visitedAt), "photo_url": opt(m.photoURL),
         "lat": opt(m.lat), "lng": opt(m.lng), "note": opt(m.note), "updated_at": iso(m.updatedAt)]
    }
    private func applyVisit(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchVisit(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(Visit(id: id, userId: uuid(row["user_id"]) ?? UUID()))
        m.userId = uuid(row["user_id"]) ?? m.userId
        m.gym = uuid(row["gym_id"]).flatMap(fetchGym)
        m.visitedAt = date(row["visited_at"]) ?? m.visitedAt
        m.photoURL = str(row["photo_url"])
        m.lat = dbl(row["lat"]); m.lng = dbl(row["lng"]); m.note = str(row["note"])
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - visit_partners
    private func encodeVisitPartner(_ m: VisitPartner) -> [String: Any] {
        ["id": lower(m.id), "visit_id": opt(m.visit?.id.uuidString.lowercased()),
         "partner_user_id": lower(m.partnerUserId), "partner_display_name": opt(m.partnerDisplayName),
         "updated_at": iso(m.updatedAt)]
    }
    private func applyVisitPartner(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchVisitPartner(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(VisitPartner(id: id, partnerUserId: uuid(row["partner_user_id"]) ?? UUID()))
        m.partnerUserId = uuid(row["partner_user_id"]) ?? m.partnerUserId
        m.partnerDisplayName = str(row["partner_display_name"])
        m.visit = uuid(row["visit_id"]).flatMap(fetchVisit)
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - workouts
    private func encodeWorkout(_ m: Workout) -> [String: Any] {
        ["id": lower(m.id), "user_id": lower(m.userId), "visit_id": opt(m.visit?.id.uuidString.lowercased()),
         "date": iso(m.date), "name": m.name, "routine_id": opt(m.routineId?.uuidString.lowercased()),
         "note": opt(m.note), "is_planned": m.isPlanned, "completed_at": opt(m.completedAt.map(iso)),
         "updated_at": iso(m.updatedAt)]
    }
    private func applyWorkout(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchWorkout(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(Workout(id: id, userId: uuid(row["user_id"]) ?? UUID()))
        m.userId = uuid(row["user_id"]) ?? m.userId
        m.visit = uuid(row["visit_id"]).flatMap(fetchVisit)
        m.date = date(row["date"]) ?? m.date
        m.name = str(row["name"]) ?? m.name
        m.routineId = uuid(row["routine_id"])
        m.note = str(row["note"])
        m.isPlanned = bool(row["is_planned"]) ?? m.isPlanned
        m.completedAt = date(row["completed_at"])
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - exercises
    private func encodeExercise(_ m: Exercise) -> [String: Any] {
        var row: [String: Any] = [
            "id": lower(m.id), "name": m.name, "muscle_group": m.muscleGroupRaw,
            "equipment": m.equipmentRaw, "is_custom": m.isCustom, "weight_mode": m.weightModeRaw,
            "updated_at": iso(m.updatedAt),
        ]
        // RLS(exercises_insert_own) は created_by = auth.uid() を要求する。プリセット(nil)や
        // 旧 uid のままだと弾かれる。push できるのは本人のローカル種目だけなので、同期中の本人 id を
        // 所有者として送る。
        if let owner = currentUserId ?? m.createdBy { row["created_by"] = lower(owner) }
        return row
    }
    private func applyExercise(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchExercise(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(Exercise(id: id, name: str(row["name"]) ?? "種目", muscleGroup: .fullBody, equipment: .other))
        m.name = str(row["name"]) ?? m.name
        m.muscleGroupRaw = str(row["muscle_group"]) ?? m.muscleGroupRaw
        m.equipmentRaw = str(row["equipment"]) ?? m.equipmentRaw
        m.isCustom = bool(row["is_custom"]) ?? m.isCustom
        m.createdBy = uuid(row["created_by"])
        m.weightModeRaw = str(row["weight_mode"]) ?? m.weightModeRaw
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - workout_exercises
    private func encodeWorkoutExercise(_ m: WorkoutExercise) -> [String: Any] {
        ["id": lower(m.id), "workout_id": opt(m.workout?.id.uuidString.lowercased()),
         "exercise_id": opt(m.exercise?.id.uuidString.lowercased()), "order_index": m.orderIndex,
         "note": opt(m.note), "superset_group": opt(m.supersetGroup), "rest_seconds": opt(m.restSeconds),
         "updated_at": iso(m.updatedAt)]
    }
    private func applyWorkoutExercise(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchWorkoutExercise(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(WorkoutExercise(id: id, orderIndex: int(row["order_index"]) ?? 0))
        m.orderIndex = int(row["order_index"]) ?? m.orderIndex
        m.note = str(row["note"])
        m.supersetGroup = int(row["superset_group"])
        m.restSeconds = int(row["rest_seconds"])
        m.workout = uuid(row["workout_id"]).flatMap(fetchWorkout)
        m.exercise = uuid(row["exercise_id"]).flatMap(fetchExercise)
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - exercise_sets（追記型）
    private func encodeExerciseSet(_ m: ExerciseSet) -> [String: Any] {
        ["id": lower(m.id), "workout_exercise_id": opt(m.workoutExercise?.id.uuidString.lowercased()),
         "set_index": m.setIndex, "weight": m.weight, "reps": m.reps, "rpe": opt(m.rpe), "rir": opt(m.rir),
         "type": m.typeRaw, "is_pr": m.isPR, "is_completed": m.isCompleted,
         "weight_mode_override": opt(m.weightModeOverrideRaw),
         "created_at": iso(m.createdAt), "updated_at": iso(m.updatedAt)]
    }
    private func applyExerciseSet(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchExerciseSet(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(ExerciseSet(id: id, setIndex: int(row["set_index"]) ?? 0))
        m.setIndex = int(row["set_index"]) ?? m.setIndex
        m.weight = dbl(row["weight"]) ?? m.weight
        m.reps = int(row["reps"]) ?? m.reps
        m.rpe = dbl(row["rpe"]); m.rir = int(row["rir"])
        m.typeRaw = str(row["type"]) ?? m.typeRaw
        m.isPR = bool(row["is_pr"]) ?? m.isPR
        m.isCompleted = bool(row["is_completed"]) ?? m.isCompleted
        m.weightModeOverrideRaw = str(row["weight_mode_override"])
        m.workoutExercise = uuid(row["workout_exercise_id"]).flatMap(fetchWorkoutExercise)
        m.createdAt = date(row["created_at"]) ?? m.createdAt
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - routines
    private func encodeRoutine(_ m: Routine) -> [String: Any] {
        ["id": lower(m.id), "user_id": lower(m.userId), "name": m.name, "note": opt(m.note), "updated_at": iso(m.updatedAt)]
    }
    private func applyRoutine(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchRoutine(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(Routine(id: id, userId: uuid(row["user_id"]) ?? UUID(), name: str(row["name"]) ?? "ルーティン"))
        m.userId = uuid(row["user_id"]) ?? m.userId
        m.name = str(row["name"]) ?? m.name
        m.note = str(row["note"])
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - routine_exercises
    private func encodeRoutineExercise(_ m: RoutineExercise) -> [String: Any] {
        ["id": lower(m.id), "routine_id": opt(m.routine?.id.uuidString.lowercased()),
         "exercise_id": opt(m.exercise?.id.uuidString.lowercased()), "order_index": m.orderIndex,
         "target_sets": m.targetSets, "target_reps": opt(m.targetReps), "rest_seconds": opt(m.restSeconds),
         "updated_at": iso(m.updatedAt)]
    }
    private func applyRoutineExercise(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchRoutineExercise(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(RoutineExercise(id: id, orderIndex: int(row["order_index"]) ?? 0))
        m.orderIndex = int(row["order_index"]) ?? m.orderIndex
        m.targetSets = int(row["target_sets"]) ?? m.targetSets
        m.targetReps = int(row["target_reps"])
        m.restSeconds = int(row["rest_seconds"])
        m.routine = uuid(row["routine_id"]).flatMap(fetchRoutine)
        m.exercise = uuid(row["exercise_id"]).flatMap(fetchExercise)
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - personal_records
    private func encodePersonalRecord(_ m: PersonalRecord) -> [String: Any] {
        ["id": lower(m.id), "user_id": lower(m.userId), "exercise_id": opt(m.exercise?.id.uuidString.lowercased()),
         "type": m.typeRaw, "value": m.value, "achieved_at": iso(m.achievedAt),
         "workout_id": opt(m.workoutId?.uuidString.lowercased()), "updated_at": iso(m.updatedAt)]
    }
    private func applyPersonalRecord(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchPersonalRecord(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(PersonalRecord(id: id, userId: uuid(row["user_id"]) ?? UUID(), type: .maxWeight, value: dbl(row["value"]) ?? 0))
        m.userId = uuid(row["user_id"]) ?? m.userId
        m.typeRaw = str(row["type"]) ?? m.typeRaw
        m.value = dbl(row["value"]) ?? m.value
        m.achievedAt = date(row["achieved_at"]) ?? m.achievedAt
        m.workoutId = uuid(row["workout_id"])
        m.exercise = uuid(row["exercise_id"]).flatMap(fetchExercise)
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - body_metrics
    private func encodeBodyMetric(_ m: BodyMetric) -> [String: Any] {
        ["id": lower(m.id), "user_id": lower(m.userId), "date": iso(m.date),
         "weight": opt(m.weight), "body_fat": opt(m.bodyFat), "measurements": m.measurements,
         "from_health_kit": m.fromHealthKit, "updated_at": iso(m.updatedAt)]
    }
    private func applyBodyMetric(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchBodyMetric(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(BodyMetric(id: id, userId: uuid(row["user_id"]) ?? UUID()))
        m.userId = uuid(row["user_id"]) ?? m.userId
        m.date = date(row["date"]) ?? m.date
        m.weight = dbl(row["weight"]); m.bodyFat = dbl(row["body_fat"])
        m.measurements = doubleDict(row["measurements"])
        m.fromHealthKit = bool(row["from_health_kit"]) ?? m.fromHealthKit
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - progress_photos
    private func encodeProgressPhoto(_ m: ProgressPhoto) -> [String: Any] {
        ["id": lower(m.id), "user_id": lower(m.userId), "date": iso(m.date),
         "photo_url": opt(m.photoURL), "visibility": m.visibilityRaw, "note": opt(m.note), "updated_at": iso(m.updatedAt)]
    }
    private func applyProgressPhoto(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchProgressPhoto(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(ProgressPhoto(id: id, userId: uuid(row["user_id"]) ?? UUID()))
        m.userId = uuid(row["user_id"]) ?? m.userId
        m.date = date(row["date"]) ?? m.date
        m.photoURL = str(row["photo_url"])
        m.visibilityRaw = str(row["visibility"]) ?? m.visibilityRaw
        m.note = str(row["note"])
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - follows
    private func encodeFollow(_ m: Follow) -> [String: Any] {
        ["id": lower(m.id), "follower_id": lower(m.followerId), "followee_id": lower(m.followeeId),
         "followee_display_name": opt(m.followeeDisplayName), "created_at": iso(m.createdAt), "updated_at": iso(m.updatedAt)]
    }
    private func applyFollow(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchFollow(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(Follow(id: id, followerId: uuid(row["follower_id"]) ?? UUID(), followeeId: uuid(row["followee_id"]) ?? UUID()))
        m.followerId = uuid(row["follower_id"]) ?? m.followerId
        m.followeeId = uuid(row["followee_id"]) ?? m.followeeId
        m.followeeDisplayName = str(row["followee_display_name"])
        m.createdAt = date(row["created_at"]) ?? m.createdAt
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - blocks
    private func encodeBlock(_ m: Block) -> [String: Any] {
        ["id": lower(m.id), "blocker_id": lower(m.blockerId), "blocked_id": lower(m.blockedId),
         "blocked_display_name": opt(m.blockedDisplayName), "created_at": iso(m.createdAt), "updated_at": iso(m.updatedAt)]
    }
    private func applyBlock(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchBlock(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(Block(id: id, blockerId: uuid(row["blocker_id"]) ?? UUID(), blockedId: uuid(row["blocked_id"]) ?? UUID()))
        m.blockerId = uuid(row["blocker_id"]) ?? m.blockerId
        m.blockedId = uuid(row["blocked_id"]) ?? m.blockedId
        m.blockedDisplayName = str(row["blocked_display_name"])
        m.createdAt = date(row["created_at"]) ?? m.createdAt
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - reports
    private func encodeReport(_ m: Report) -> [String: Any] {
        ["id": lower(m.id), "reporter_id": lower(m.reporterId), "reported_user_id": lower(m.reportedUserId),
         "context_type": opt(m.contextType), "context_id": opt(m.contextId?.uuidString.lowercased()),
         "reason": m.reason, "detail": opt(m.detail), "created_at": iso(m.createdAt), "updated_at": iso(m.updatedAt)]
    }
    private func applyReport(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchReport(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(Report(id: id, reporterId: uuid(row["reporter_id"]) ?? UUID(), reportedUserId: uuid(row["reported_user_id"]) ?? UUID(), reason: str(row["reason"]) ?? "other"))
        m.reporterId = uuid(row["reporter_id"]) ?? m.reporterId
        m.reportedUserId = uuid(row["reported_user_id"]) ?? m.reportedUserId
        m.contextType = str(row["context_type"])
        m.contextId = uuid(row["context_id"])
        m.reason = str(row["reason"]) ?? m.reason
        m.detail = str(row["detail"])
        m.createdAt = date(row["created_at"]) ?? m.createdAt
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - feed_items
    private func encodeFeedItem(_ m: FeedItem) -> [String: Any] {
        ["id": lower(m.id), "user_id": lower(m.userId), "author_display_name": opt(m.authorDisplayName),
         "type": m.typeRaw, "ref_id": lower(m.refId), "summary": opt(m.summary), "visibility": m.visibilityRaw,
         "created_at": iso(m.createdAt), "updated_at": iso(m.updatedAt)]
    }
    private func applyFeedItem(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchFeedItem(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(FeedItem(id: id, userId: uuid(row["user_id"]) ?? UUID(), type: .visit, refId: uuid(row["ref_id"]) ?? UUID()))
        m.userId = uuid(row["user_id"]) ?? m.userId
        m.authorDisplayName = str(row["author_display_name"])
        m.typeRaw = str(row["type"]) ?? m.typeRaw
        m.refId = uuid(row["ref_id"]) ?? m.refId
        m.summary = str(row["summary"])
        m.visibilityRaw = str(row["visibility"]) ?? m.visibilityRaw
        m.createdAt = date(row["created_at"]) ?? m.createdAt
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - post_reactions（いいね/応援）
    private func encodePostReaction(_ m: PostReaction) -> [String: Any] {
        ["id": lower(m.id), "user_id": lower(m.userId), "feed_item_id": lower(m.feedItemId),
         "kind": m.kindRaw, "created_at": iso(m.createdAt), "updated_at": iso(m.updatedAt)]
    }
    private func applyPostReaction(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchPostReaction(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(PostReaction(id: id, userId: uuid(row["user_id"]) ?? UUID(), feedItemId: uuid(row["feed_item_id"]) ?? UUID()))
        m.userId = uuid(row["user_id"]) ?? m.userId
        m.feedItemId = uuid(row["feed_item_id"]) ?? m.feedItemId
        m.kindRaw = str(row["kind"]) ?? m.kindRaw
        m.createdAt = date(row["created_at"]) ?? m.createdAt
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - products（pull のみ＝サーバ管理カタログ）
    private func applyProduct(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let name = str(row["name"]) ?? "商品"
        let existing = fetchProduct(id)
        // id 不一致でも同名のローカル seed があれば置き換える（ローカル/サーバの二重表示を防ぐ）。
        if existing == nil, let localSeed = fetchProductByName(name) {
            context.delete(localSeed)
        }
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(Product(id: id, name: name, price: decimal(row["price"]) ?? 0))
        m.name = str(row["name"]) ?? m.name
        m.productDescription = str(row["description"])
        m.price = decimal(row["price"]) ?? m.price
        m.imageURL = str(row["image_url"])
        m.category = str(row["category"])
        m.goalTags = strArray(row["goal_tags"])
        m.affiliateURL = str(row["affiliate_url"])
        m.merchant = str(row["merchant"])
        m.servingsPerUnit = int(row["servings_per_unit"])
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - supply_logs
    private func encodeSupplyLog(_ m: SupplyLog) -> [String: Any] {
        // m.product は inverse 無し関連。参照先(seed商品)がカタログ同期で削除されると宙ぶらりんになり、
        // アクセスした瞬間に SwiftData がアサーションでクラッシュする（push のたびに発火）。
        // 関連を読まず、productName から安全に product_id を解決する。
        let productId = m.productName.flatMap { fetchProductByName($0)?.id }
        return ["id": lower(m.id), "user_id": lower(m.userId),
                "product_id": opt(productId?.uuidString.lowercased()),
                "date": iso(m.date), "amount": m.amount, "product_name": opt(m.productName), "updated_at": iso(m.updatedAt)]
    }
    private func applySupplyLog(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchSupplyLog(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(SupplyLog(id: id, userId: uuid(row["user_id"]) ?? UUID()))
        m.userId = uuid(row["user_id"]) ?? m.userId
        m.product = uuid(row["product_id"]).flatMap(fetchProduct)
        m.date = date(row["date"]) ?? m.date
        m.amount = dbl(row["amount"]) ?? m.amount
        m.productName = str(row["product_name"])
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - subscriptions
    private func encodeSubscription(_ m: Subscription) -> [String: Any] {
        ["id": lower(m.id), "user_id": lower(m.userId), "tier": m.tierRaw, "status": m.statusRaw,
         "started_at": iso(m.startedAt), "updated_at": iso(m.updatedAt)]
    }
    private func applySubscription(_ row: [String: Any]) {
        guard let id = uuid(row["id"]) else { return }
        let existing = fetchSubscription(id)
        if remoteIsStale(localUpdatedAt: existing?.updatedAt, row) { return }
        let m = existing ?? insert(Subscription(id: id, userId: uuid(row["user_id"]) ?? UUID()))
        m.userId = uuid(row["user_id"]) ?? m.userId
        m.tierRaw = str(row["tier"]) ?? m.tierRaw
        m.statusRaw = str(row["status"]) ?? m.statusRaw
        m.startedAt = date(row["started_at"]) ?? m.startedAt
        m.updatedAt = date(row["updated_at"]) ?? m.updatedAt
        m.isDirty = false
    }

    // MARK: - 取得ヘルパ（id で 1 件）
    @discardableResult private func insert<T: PersistentModel>(_ model: T) -> T { context.insert(model); return model }
    private func fetchProfile(_ id: UUID) -> Profile? { first(FetchDescriptor<Profile>(predicate: #Predicate { $0.id == id })) }
    private func fetchGym(_ id: UUID) -> Gym? { first(FetchDescriptor<Gym>(predicate: #Predicate { $0.id == id })) }
    private func fetchGymEquipment(_ id: UUID) -> GymEquipment? { first(FetchDescriptor<GymEquipment>(predicate: #Predicate { $0.id == id })) }
    private func fetchVisit(_ id: UUID) -> Visit? { first(FetchDescriptor<Visit>(predicate: #Predicate { $0.id == id })) }
    private func fetchVisitPartner(_ id: UUID) -> VisitPartner? { first(FetchDescriptor<VisitPartner>(predicate: #Predicate { $0.id == id })) }
    private func fetchWorkout(_ id: UUID) -> Workout? { first(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })) }
    private func fetchExercise(_ id: UUID) -> Exercise? { first(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })) }
    private func fetchWorkoutExercise(_ id: UUID) -> WorkoutExercise? { first(FetchDescriptor<WorkoutExercise>(predicate: #Predicate { $0.id == id })) }
    private func fetchExerciseSet(_ id: UUID) -> ExerciseSet? { first(FetchDescriptor<ExerciseSet>(predicate: #Predicate { $0.id == id })) }
    private func fetchRoutine(_ id: UUID) -> Routine? { first(FetchDescriptor<Routine>(predicate: #Predicate { $0.id == id })) }
    private func fetchRoutineExercise(_ id: UUID) -> RoutineExercise? { first(FetchDescriptor<RoutineExercise>(predicate: #Predicate { $0.id == id })) }
    private func fetchPersonalRecord(_ id: UUID) -> PersonalRecord? { first(FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.id == id })) }
    private func fetchBodyMetric(_ id: UUID) -> BodyMetric? { first(FetchDescriptor<BodyMetric>(predicate: #Predicate { $0.id == id })) }
    private func fetchProgressPhoto(_ id: UUID) -> ProgressPhoto? { first(FetchDescriptor<ProgressPhoto>(predicate: #Predicate { $0.id == id })) }
    private func fetchFollow(_ id: UUID) -> Follow? { first(FetchDescriptor<Follow>(predicate: #Predicate { $0.id == id })) }
    private func fetchBlock(_ id: UUID) -> Block? { first(FetchDescriptor<Block>(predicate: #Predicate { $0.id == id })) }
    private func fetchReport(_ id: UUID) -> Report? { first(FetchDescriptor<Report>(predicate: #Predicate { $0.id == id })) }
    private func fetchFeedItem(_ id: UUID) -> FeedItem? { first(FetchDescriptor<FeedItem>(predicate: #Predicate { $0.id == id })) }
    private func fetchPostReaction(_ id: UUID) -> PostReaction? { first(FetchDescriptor<PostReaction>(predicate: #Predicate { $0.id == id })) }
    private func fetchProduct(_ id: UUID) -> Product? { first(FetchDescriptor<Product>(predicate: #Predicate { $0.id == id })) }
    private func fetchProductByName(_ name: String) -> Product? { first(FetchDescriptor<Product>(predicate: #Predicate { $0.name == name })) }
    private func fetchSupplyLog(_ id: UUID) -> SupplyLog? { first(FetchDescriptor<SupplyLog>(predicate: #Predicate { $0.id == id })) }
    private func fetchSubscription(_ id: UUID) -> Subscription? { first(FetchDescriptor<Subscription>(predicate: #Predicate { $0.id == id })) }

    private func first<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> T? {
        var d = descriptor; d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    // MARK: - 値変換ヘルパ（NSNull / NSNumber / 文字列を吸収）
    private func iso(_ d: Date) -> String { ISO8601DateFormatter.supabase.string(from: d) }
    private func lower(_ id: UUID) -> String { id.uuidString.lowercased() }
    /// nil を JSON null（NSNull）として明示送出する（merge-duplicates で値をクリアできるように）。
    /// ジェネリックで受けることで Optional の二重ラップ（JSON 化失敗）を避ける。
    private func opt<T>(_ v: T?) -> Any {
        if let v { return v }
        return NSNull()
    }

    private func str(_ v: Any?) -> String? {
        guard let v, !(v is NSNull) else { return nil }
        return v as? String
    }
    private func uuid(_ v: Any?) -> UUID? { (str(v)).flatMap { UUID(uuidString: $0) } }
    private func date(_ v: Any?) -> Date? {
        guard let s = str(v) else { return nil }
        // PostgREST の timestamptz は小数秒の有無が混在しうるため両方試す。
        return ISO8601DateFormatter.supabase.date(from: s) ?? ISO8601DateFormatter.plain.date(from: s)
    }
    private func bool(_ v: Any?) -> Bool? {
        guard let v, !(v is NSNull) else { return nil }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        return nil
    }
    private func int(_ v: Any?) -> Int? {
        guard let v, !(v is NSNull) else { return nil }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }
    private func dbl(_ v: Any?) -> Double? {
        guard let v, !(v is NSNull) else { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
    private func decimal(_ v: Any?) -> Decimal? {
        guard let v, !(v is NSNull) else { return nil }
        if let n = v as? NSNumber { return n.decimalValue }
        if let s = v as? String { return Decimal(string: s) }
        return nil
    }
    private func strArray(_ v: Any?) -> [String] { (v as? [String]) ?? [] }
    private func doubleDict(_ v: Any?) -> [String: Double] {
        guard let dict = v as? [String: Any] else { return [:] }
        var out: [String: Double] = [:]
        for (k, value) in dict {
            if let n = value as? NSNumber { out[k] = n.doubleValue }
            else if let d = value as? Double { out[k] = d }
        }
        return out
    }
}
