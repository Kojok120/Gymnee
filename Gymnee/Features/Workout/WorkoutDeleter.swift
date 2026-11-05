import Foundation
import SwiftData

/// ワークアウトの削除（#168）。記録一覧・日別・フィード・自分の投稿のどこから消しても、同じ手順で消す。
///
/// 手順: 端末から消して保存 → **保存できたときだけ**写真のファイルを消し、サーバーの削除と投稿の削除を積む。
/// 保存に失敗したのにサーバーだけ消えると、端末とサーバーが食い違うため（以前は日別の画面だけ保存の結果を見ずに積んでいた）。
@MainActor
enum WorkoutDeleter {

    /// 確認文に書く「一緒に消えるもの」。
    static func facts(for workout: Workout, context: ModelContext) -> DeletionCopy.WorkoutFacts {
        let exercises = workout.exercises.filter { !$0.sets.isEmpty }
        let wid = workout.id
        let isPublished = ((try? context.fetchCount(FetchDescriptor<FeedItem>(predicate: #Predicate { $0.id == wid }))) ?? 0) > 0
        let reactions = isPublished
            ? (try? context.fetchCount(FetchDescriptor<PostReaction>(predicate: #Predicate { $0.feedItemId == wid }))) ?? 0
            : 0
        return DeletionCopy.WorkoutFacts(
            exercises: exercises.count,
            sets: exercises.reduce(0) { $0 + $1.sets.count },
            isPublished: isPublished,
            reactions: reactions,
            hasPhoto: workout.localPhotoFilename != nil
        )
    }

    /// 消せたら true。保存に失敗したら端末の変更を戻し、サーバーには何も送らない。
    @discardableResult
    static func delete(_ workout: Workout, context: ModelContext, sync: LocalSyncEngine) -> Bool {
        let id = workout.id
        let photo = workout.localPhotoFilename
        context.delete(workout) // 配下の workout_exercises / exercise_sets は cascade で消える
        do {
            try context.save()
        } catch {
            context.rollback()
            return false
        }
        PhotoStore.delete(photo)
        sync.enqueue(PendingChange(entity: "workouts", recordId: id, operation: .delete, updatedAt: .now))
        FeedPublisher.deleteFeedItem(forRefId: id, context: context, sync: sync)
        return true
    }

    /// 投稿を取り下げるときに要る、いまの利用者の情報。
    struct Author {
        let userId: UUID
        let name: String?
        let isPermanentAccount: Bool
    }

    /// 確認の中身を作る。投稿していれば「非公開にする」も出す。
    static func request(
        for workout: Workout,
        author: Author?,
        context: ModelContext,
        sync: LocalSyncEngine,
        onFailure: @escaping @MainActor () -> Void = {},
        onDone: @escaping @MainActor () -> Void = {}
    ) -> DeletionRequest {
        let f = facts(for: workout, context: context)
        let workoutId = workout.id
        var makePrivate: (@MainActor () -> Void)?
        if f.isPublished, let author {
            makePrivate = {
                FeedPublisher.setVisibility(.private, forRefId: workoutId, type: .workout, userId: author.userId,
                                            authorName: author.name, isPermanentAccount: author.isPermanentAccount,
                                            context: context, sync: sync)
                Task { await sync.syncNow(force: true) }
                onDone()
            }
        }
        return DeletionRequest(
            title: DeletionCopy.workoutTitle,
            message: DeletionCopy.workoutMessage(f),
            onDelete: {
                if delete(workout, context: context, sync: sync) { onDone() } else { onFailure() }
            },
            makePrivate: makePrivate
        )
    }
}
