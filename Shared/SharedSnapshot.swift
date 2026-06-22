import Foundation

/// アプリ本体・Widget・Watch で共有する軽量スナップショット（§6.10）。
/// SwiftData を拡張から直接読むのは重いため、本体が更新する小さな JSON を App Group 経由で配る。
struct GymneeSnapshot: Codable, Equatable, Sendable {
    var streak: Int = 0
    var weeklyCount: Int = 0
    var weeklyGoal: Int = 3
    var lastWorkoutName: String?
    var lastWorkoutDate: Date?
    var nextPlannedName: String?
    var nextPlannedDate: Date?
    var updatedAt: Date = .init(timeIntervalSince1970: 0)

    static let empty = GymneeSnapshot()
}

/// App Group 共有ストア。エンタイトルメント未適用時は標準 UserDefaults にフォールバック（縮退）。
enum SharedStore {
    static let appGroup = "group.com.gymnee.app"
    private static let snapshotKey = "gymnee.snapshot"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func save(_ snapshot: GymneeSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
    }

    static func load() -> GymneeSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(GymneeSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    // MARK: - Watch → Phone クイックチェックイン要求（§6.10）
    // 端末間は WatchConnector(WCSession) が運ぶ。本キューは「同一端末内の受け渡し＋アプリ未起動時の取りこぼし防止」用。
    private static let pendingKey = "gymnee.pendingWatchCheckIns"

    /// Watch から「クイックチェックイン」を要求（タイムスタンプを積む）。
    static func addPendingCheckIn(at date: Date = .init()) {
        var dates = (defaults.array(forKey: pendingKey) as? [Double]) ?? []
        dates.append(date.timeIntervalSince1970)
        defaults.set(dates, forKey: pendingKey)
    }

    /// 本体側でキューを取り出してクリアする。
    static func consumePendingCheckIns() -> [Date] {
        let dates = (defaults.array(forKey: pendingKey) as? [Double]) ?? []
        defaults.removeObject(forKey: pendingKey)
        return dates.map { Date(timeIntervalSince1970: $0) }
    }

    // MARK: - 認証ユーザーID（App Intent / Siri / 拡張は別プロセスで standard を読めないため App Group にも保持）
    private static let userIdKey = "gymnee.auth.userId"

    /// 現在のユーザーIDを App Group に保存（サインイン/復元時に本体が呼ぶ）。nil で消去。
    static func saveUserId(_ id: UUID?) {
        if let id { defaults.set(id.uuidString, forKey: userIdKey) }
        else { defaults.removeObject(forKey: userIdKey) }
    }

    /// App Group 保持のユーザーIDを読む（App Intent / Siri から）。
    static func userId() -> UUID? {
        defaults.string(forKey: userIdKey).flatMap(UUID.init(uuidString:))
    }
}
