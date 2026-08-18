import Foundation
import SwiftData

/// profiles の通知・ライブ配信設定をローカルで保持する。
///
/// Profile へ後付けの保存プロパティを追加すると既存SwiftDataスキーマとの互換性を失うため、
/// 設定専用モデルとして追加し、同期時は profiles の列へ統合する。
@Model
final class ProfileNotificationSettings {
    @Attribute(.unique) var userId: UUID
    /// 自分のトレーニング開始をフォロワーへ通知するか。実時間の行動共有なので既定はオフ。
    var shareLiveStart: Bool
    /// フォロー中の人のトレーニング開始通知を受け取るか。
    var notifyLiveStart: Bool
    /// フォロー中の人の投稿通知を受け取るか。
    var notifyPost: Bool

    init(
        userId: UUID,
        shareLiveStart: Bool = false,
        notifyLiveStart: Bool = true,
        notifyPost: Bool = true
    ) {
        self.userId = userId
        self.shareLiveStart = shareLiveStart
        self.notifyLiveStart = notifyLiveStart
        self.notifyPost = notifyPost
    }
}

/// 旧AppStorageのライブ配信設定を、新しいprofiles同期設定へ一度だけ引き上げる。
@MainActor
enum ProfileNotificationSettingsMigration {
    static func migrateLegacyLiveShare(userId: UUID, context: ModelContext, sync: LocalSyncEngine) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: LiveSessionService.legacyShareKey) else { return }

        let profileDescriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.id == userId })
        guard let profile = try? context.fetch(profileDescriptor).first else { return }
        let settingsDescriptor = FetchDescriptor<ProfileNotificationSettings>(
            predicate: #Predicate { $0.userId == userId }
        )
        let settings: ProfileNotificationSettings
        if let existing = try? context.fetch(settingsDescriptor).first {
            settings = existing
        } else {
            let created = ProfileNotificationSettings(userId: userId)
            context.insert(created)
            settings = created
        }

        guard !settings.shareLiveStart else {
            defaults.removeObject(forKey: LiveSessionService.legacyShareKey)
            return
        }

        settings.shareLiveStart = true
        profile.updatedAt = .now
        profile.isDirty = true
        do {
            try context.save()
        } catch {
            context.rollback()
            return
        }
        defaults.removeObject(forKey: LiveSessionService.legacyShareKey)
        sync.enqueue(PendingChange(entity: "profiles", recordId: profile.id, operation: .upsert, updatedAt: profile.updatedAt))
    }
}
