import Foundation
import Observation

/// 「いまトレーニング中」の配信と、それに対する応援。
///
/// **ローカル（SwiftData）には持たない**。オンラインでしか意味が無い情報で、端末を正にすると
/// 「終わっていないセッション」がオフラインで残り続ける。サーバが正で、失敗しても黙って諦める。
/// 記録そのものはオフラインで完結しなければならないので、**ここでの失敗は記録を一切妨げない**。
@MainActor
@Observable
final class LiveSessionService {

    /// 配信するか（送る側の設定）。**既定はオフ**。
    /// トレ中であることを知らせるのは居場所と行動を実時間で明かすことなので、
    /// 明示的にオンにした人だけが流れる。
    static let shareKey = "gymnee.live.share"

    /// いま配信しているセッション。記録中だけ入る。
    private(set) var currentSessionId: UUID?
    /// 自分のセッションに届いた応援（記録画面に残すぶん・古い順）。
    private(set) var cheers: [Cheer] = []

    struct Cheer: Identifiable, Equatable, Sendable {
        let id: UUID
        let name: String
        let kind: String
        let at: Date

        /// スタンプ。`post_reactions` と同じ語彙に揃えてある。
        var emoji: String {
            switch kind {
            case "fire": return "🔥"
            case "strong": return "💪"
            case "clap": return "👏"
            default: return "❤️"
            }
        }
    }

    /// リモート未設定（`Supabase.plist` 無し）なら nil のまま＝配信も応援もしない。
    private var client: SupabaseClient?

    func configure(client: SupabaseClient) { self.client = client }

    private var shares: Bool { UserDefaults.standard.bool(forKey: Self.shareKey) }

    /// 記録を始めたことを配信する。設定がオフ・未サインインなら何もしない。
    func start() async {
        guard shares, currentSessionId == nil, let client else { return }
        guard await client.isAuthenticated else { return }
        cheers = []
        currentSessionId = try? await client.startLiveSession()
    }

    /// 配信を終える。終えないと期限（3時間）まで「トレーニング中」のままになるので、
    /// 記録の完了・破棄のどちらからも必ず呼ぶ。
    func end() async {
        guard let id = currentSessionId, let client else { currentSessionId = nil; return }
        currentSessionId = nil
        cheers = []
        try? await client.endLiveSession(id: id)
    }

    /// 届いた応援を取り直す。押されるたびに取りに行かず、画面が出たときと復帰時だけ呼ぶ。
    func refreshCheers() async {
        guard let id = currentSessionId, let client else { return }
        guard let rows = try? await client.cheers(sessionId: id) else { return }
        let userIds = rows.compactMap { ($0["user_id"] as? String).flatMap(UUID.init(uuidString:)) }
        let names = (try? await client.displayNames(userIds: Array(Set(userIds)))) ?? [:]
        cheers = rows.compactMap { row in
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let userId = (row["user_id"] as? String).flatMap(UUID.init(uuidString:))
            else { return nil }
            return Cheer(
                id: id,
                name: names[userId] ?? "フレンド",
                kind: (row["kind"] as? String) ?? "fire",
                at: (row["created_at"] as? String).flatMap(ISO8601DateFormatter.supabase.date(from:)) ?? .now
            )
        }
    }

    /// プッシュで届いた応援をその場で足す（取り直しを待たずに画面へ出す）。
    /// 同じものが取り直しでも来るので、id ではなく名前と種類で重複を避ける。
    func appendFromPush(name: String, kind: String, at: Date = .now) {
        guard currentSessionId != nil else { return }
        guard !cheers.contains(where: { $0.name == name && $0.kind == kind }) else { return }
        cheers.append(Cheer(id: UUID(), name: name, kind: kind, at: at))
    }

    /// いまトレーニング中の人（フォロー中のみ）。応援する側の一覧に使う。
    func liveFriends() async -> [LiveFriend] {
        guard let client, await client.isAuthenticated else { return [] }
        guard let rows = try? await client.liveSessions() else { return [] }
        let userIds = rows.compactMap { ($0["user_id"] as? String).flatMap(UUID.init(uuidString:)) }
        let names = (try? await client.displayNames(userIds: Array(Set(userIds)))) ?? [:]
        return rows.compactMap { row in
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let userId = (row["user_id"] as? String).flatMap(UUID.init(uuidString:))
            else { return nil }
            return LiveFriend(
                sessionId: id,
                userId: userId,
                name: names[userId] ?? "フレンド",
                startedAt: (row["started_at"] as? String)
                    .flatMap(ISO8601DateFormatter.supabase.date(from:)) ?? .now
            )
        }
    }

    /// 応援を送る。連打しても同じスタンプは 1 回（サーバの一意制約）。
    func cheer(sessionId: UUID, kind: String) async {
        guard let client else { return }
        try? await client.sendCheer(sessionId: sessionId, kind: kind)
    }

    struct LiveFriend: Identifiable, Equatable, Sendable {
        let sessionId: UUID
        let userId: UUID
        let name: String
        let startedAt: Date
        var id: UUID { sessionId }
    }
}
