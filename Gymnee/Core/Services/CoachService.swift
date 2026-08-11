import Foundation
import SwiftData

/// AI コーチとの会話を持つサービス（#79）。
///
/// 会話はローカル（SwiftData の `CoachMessage`）が正で、サーバーへは同期で送る。
/// 送信できなかった場合でも会話は端末に残り、あとから同期される（オフラインファースト）。
///
/// LLM が使えない（鍵未設定・通信断）ときは `CoachConsultation` の静的な答えに落とす。
/// 黙ってしまうと「壊れている」ように見えるため、必ず何かを返す。
@MainActor
@Observable
final class CoachService {

    /// リモート呼び出し先。未設定ならローカルのみで動く。
    private var client: SupabaseClient?
    /// 会話をサーバーへ送るための同期エンジン。未設定ならローカルのみに残る。
    private weak var sync: LocalSyncEngine?

    /// 送信中か（UI の入力欄を止めるために見る）。
    private(set) var isSending = false
    /// 直近の失敗理由（UI に出すことはせず、フォールバック文言の選択に使う）。
    private(set) var lastFailure: Failure?

    enum Failure: Equatable {
        /// Edge Function に鍵が無い。
        case notConfigured
        /// 通信断・その他。
        case unreachable
    }

    /// 今日送った数（無料枠の判定に使う）。日付が変わったら数え直す。
    var sentToday: Int {
        get {
            let last = UserDefaults.standard.object(forKey: Self.lastSentKey) as? Date
            if CoachQuota.resetIfNeeded(lastSent: last, now: .now) { return 0 }
            return UserDefaults.standard.integer(forKey: Self.sentCountKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.sentCountKey)
            UserDefaults.standard.set(Date.now, forKey: Self.lastSentKey)
        }
    }

    private static let sentCountKey = "gymnee.coach.sentToday"
    private static let lastSentKey = "gymnee.coach.lastSentAt"

    func configure(client: SupabaseClient?, sync: LocalSyncEngine?) {
        self.client = client
        self.sync = sync
    }

    /// 会話 1 通を outbox に積む。**これを忘れると会話が端末から出ていかない**。
    /// `coach_messages` はテーブルも RLS も用意してあるのに、積み忘れで
    /// サーバーに 1 件も保存されていなかった（機種変更で会話が全部消える状態だった）。
    private func enqueue(_ message: CoachMessage) {
        sync?.enqueue(PendingChange(
            entity: "coach_messages",
            recordId: message.id,
            operation: .upsert,
            updatedAt: message.updatedAt
        ))
    }

    /// リモートに繋がる状態か（未設定なら選択肢式の相談に留める）。
    var isRemoteAvailable: Bool { client != nil }

    // MARK: - 送信

    /// ユーザーの発言を送り、返答を会話に積む。
    ///
    /// 保存はローカルに即時。リモートは best-effort で、失敗しても会話は成立させる。
    @discardableResult
    func send(
        _ text: String,
        userId: UUID,
        brief: CoachBrief,
        mode: CoachMode,
        history: [CoachMessage],
        context: ModelContext
    ) async -> CoachMessage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return nil }

        isSending = true
        defer { isSending = false }

        // ユーザーの発言を先に残す。返答に失敗しても発言は消えない。
        let outgoing = CoachMessage(userId: userId, isFromCoach: false, text: trimmed)
        context.insert(outgoing)
        try? context.save()
        enqueue(outgoing)
        sentToday += 1

        let reply = await requestReply(
            message: trimmed, brief: brief, mode: mode,
            history: history + [outgoing]
        )

        let incoming = CoachMessage(
            userId: userId,
            isFromCoach: true,
            text: reply.text,
            proposalJSON: reply.proposalJSON
        )
        context.insert(incoming)
        try? context.save()
        enqueue(incoming)
        return incoming
    }

    /// 返答の中身（本文と、あればメニュー提案）。
    private struct Reply {
        let text: String
        let proposalJSON: String?
    }

    private func requestReply(
        message: String, brief: CoachBrief, mode: CoachMode, history: [CoachMessage]
    ) async -> Reply {
        guard let client else {
            lastFailure = .notConfigured
            return Reply(text: CoachPersona.notConfigured, proposalJSON: nil)
        }
        do {
            let result = try await client.coachChat(
                message: message,
                history: Self.wireHistory(history),
                brief: brief.payload,
                decidesMenu: mode.decidesMenu
            )
            lastFailure = nil
            // 壊れた返答（JSON の断片など）はそのまま出さない。
            let text = CoachPersona.isPresentable(result.text) ? result.text : CoachPersona.malformed
            return Reply(text: text, proposalJSON: Self.encodeProposal(result))
        } catch {
            // 503(not_configured) と通信断で文言を変える。どちらも会話は続けられる形にする。
            let isNotConfigured = "\(error)".contains("503")
            lastFailure = isNotConfigured ? .notConfigured : .unreachable
            return Reply(
                text: isNotConfigured ? CoachPersona.notConfigured : CoachPersona.offlineFallback,
                proposalJSON: nil
            )
        }
    }

    /// Edge Function に渡す会話履歴。直近 12 通に絞る（コストと文脈のバランス）。
    static func wireHistory(_ messages: [CoachMessage]) -> [[String: String]] {
        messages.suffix(12).map { ["role": $0.isFromCoach ? "coach" : "user", "text": $0.text] }
    }

    private static func encodeProposal(_ reply: SupabaseClient.CoachReply) -> String? {
        guard reply.hasPlan else { return nil }
        let payload: [String: Any] = [
            "title": reply.planTitle ?? "今日のメニュー",
            "exercises": reply.exercises.map {
                ["name": $0.name, "sets": $0.sets, "reps": $0.reps, "weightKg": $0.weight] as [String: Any]
            },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 提案の取り込み

    /// コーチの提案を今日の計画（`PlannedWorkout`）に落とす。
    /// 既に今日の計画があれば置き換える（コーチが決め直した、という意味になる）。
    @discardableResult
    func applyProposal(
        _ message: CoachMessage,
        userId: UUID,
        context: ModelContext,
        calendar: Calendar = .current
    ) -> PlannedWorkout? {
        guard let json = message.proposalJSON,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let title = (obj["title"] as? String) ?? "今日のメニュー"
        let exercises = obj["exercises"] as? [[String: Any]] ?? []
        guard !exercises.isEmpty else { return nil }

        let today = calendar.startOfDay(for: .now)
        // 今日ぶんの既存計画は消してから入れる（重複した「今日のクエスト」を作らない）。
        let existing = (try? context.fetch(
            FetchDescriptor<PlannedWorkout>(predicate: #Predicate { $0.userId == userId })
        )) ?? []
        for plan in existing where calendar.isDate(plan.date, inSameDayAs: today) && !plan.isDone {
            context.delete(plan)
        }

        let detail = try? JSONSerialization.data(withJSONObject: exercises)
        let planned = PlannedWorkout(
            userId: userId,
            date: today,
            title: title,
            note: nil
        )
        planned.detailJSON = detail.flatMap { String(data: $0, encoding: .utf8) }
        context.insert(planned)

        message.isApplied = true
        message.updatedAt = .now
        message.isDirty = true
        try? context.save()
        enqueue(message) // 取り込み済みの印もサーバーへ（別端末で二度提案を適用させない）
        return planned
    }
}
