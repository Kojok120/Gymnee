import Foundation

/// 同期 outbox の永続化（§3 / §7）。未送出の変更を JSON ファイルに保存し、再起動後も保持する。
/// オフラインで記録 → 復帰時に Supabase へ送出、という前提を満たすために必須。
enum OutboxStore {
    /// 既定の保存先（Application Support/gymnee_outbox.json）。
    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appendingPathComponent("gymnee_outbox.json")
    }

    static func load(from url: URL) -> [PendingChange] {
        guard let data = try? Data(contentsOf: url),
              let changes = try? JSONDecoder().decode([PendingChange].self, from: data)
        else { return [] }
        return changes
    }

    static func save(_ changes: [PendingChange], to url: URL) {
        guard let data = try? JSONEncoder().encode(changes) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
