import Foundation

/// ウィジェットとレストの Live Activity に出す絵と週ボス（issue #155）。
///
/// 拡張からドット絵の描画コード一式（スプライト・パレット・見た目の解決）を読むのは重いので、
/// 本体が自分のキャラと今週のボスを PNG に描いて App Group に置き、拡張は画像として貼るだけにする。
/// 週ボスの残り HP は本体がサーバーから読んだ値を控える（拡張は通信しない）。
enum WidgetArtwork {
    static let characterFile = "widget-character.png"
    static let bossFile = "widget-boss.png"
    private static let bossKey = "gymnee.widget.boss"

    /// 今週のボス（ウィジェットに出す分だけ）。
    struct Boss: Codable, Equatable, Sendable {
        var name: String
        var remainingHP: Int
        var totalHP: Int
        var defeated: Bool
        /// どの週の値か。週が変わったら古い値は出さない。
        var weekStart: Date
    }

    /// 絵を置く場所（App Group のコンテナ）。エンタイトルメントが無ければ nil（拡張は絵なしで描く）。
    static func fileURL(_ name: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent(name)
    }

    private static var defaults: UserDefaults { UserDefaults(suiteName: SharedStore.appGroup) ?? .standard }

    static func saveBoss(_ boss: Boss?) {
        guard let boss, let data = try? JSONEncoder().encode(boss) else {
            defaults.removeObject(forKey: bossKey)
            return
        }
        defaults.set(data, forKey: bossKey)
    }

    static func loadBoss() -> Boss? {
        guard let data = defaults.data(forKey: bossKey) else { return nil }
        return try? JSONDecoder().decode(Boss.self, from: data)
    }

    /// その時刻の週のボスか（週は月曜 0:00 始まり。拡張でも同じ規則で判定できるよう、ここに置く）。
    static func isCurrent(_ boss: Boss, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(boss.weekStart)
        return elapsed >= 0 && elapsed < 7 * 24 * 60 * 60
    }

    /// 最後の記録からこの日数が経つと、ウィジェットのキャラは寝ている。
    static let sleepAfterDays = 3

    static func isSleeping(lastWorkoutDate: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastWorkoutDate else { return true }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastWorkoutDate),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return days >= sleepAfterDays
    }
}
