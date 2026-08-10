import Foundation
import SwiftData

/// コーチとの会話 1 通。
///
/// ローカル（SwiftData）を正とし、`isDirty` の立った行を outbox 経由でサーバーへ送る
/// （他のモデルと同じ扱い）。サーバー側は RLS で本人のみ読み書きできる。
///
/// 会話は端末をまたいで続くべきものなので同期対象にする。ただし**内容は本人以外に一切見せない**：
/// フィードにも出さず、公開範囲の概念も持たない。
@Model
final class CoachMessage {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    /// 発言者。`isFromCoach` が true ならコーチ、false ならユーザー。
    var isFromCoach: Bool
    var text: String
    /// 送信時刻（会話の並び順）。
    var createdAt: Date
    /// コーチの返答に添えられた計画の提案（`[PlanExercise]` 相当の JSON）。無ければ nil。
    var proposalJSON: String?
    /// 提案を実際に取り込んだか。取り込み済みの提案を二度適用しないための印。
    var isApplied: Bool
    var updatedAt: Date
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        userId: UUID,
        isFromCoach: Bool,
        text: String,
        createdAt: Date = .now,
        proposalJSON: String? = nil,
        isApplied: Bool = false,
        updatedAt: Date = .now,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.isFromCoach = isFromCoach
        self.text = text
        self.createdAt = createdAt
        self.proposalJSON = proposalJSON
        self.isApplied = isApplied
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}

extension CoachMessage {
    /// 提案が付いていて、まだ取り込んでいない返答か。
    var hasPendingProposal: Bool {
        proposalJSON?.isEmpty == false && !isApplied
    }
}
