import SwiftUI
import SwiftData

/// UGC安全（App Store ガイドライン1.2.5）: ブロック・通報の共有ロジックとUI。
/// ソーシャル機能（フォロー/検索/フィード）はユーザー投稿を扱うため、
/// 「不適切コンテンツの通報」「迷惑ユーザーのブロック」「ガイドライン同意」を提供する。

enum ModerationReason: String, CaseIterable, Identifiable {
    case spam, harassment, inappropriate, impersonation, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .spam:          return "スパム・宣伝"
        case .harassment:    return "嫌がらせ・いじめ"
        case .inappropriate: return "不適切なコンテンツ"
        case .impersonation: return "なりすまし"
        case .other:         return "その他"
        }
    }
}

@MainActor
enum Moderation {
    /// 対象ユーザーをブロックする。双方向のフォローを解除し、Block を作成して同期する（冪等）。
    static func block(blockerId: UUID, blockedId: UUID, displayName: String?,
                      context: ModelContext, sync: LocalSyncEngine) {
        guard blockerId != blockedId else { return }
        // 双方向のフォロー関係を解除（自分→相手 / 相手→自分）。
        let related = (try? context.fetch(FetchDescriptor<Follow>(predicate: #Predicate {
            ($0.followerId == blockerId && $0.followeeId == blockedId) ||
            ($0.followerId == blockedId && $0.followeeId == blockerId)
        }))) ?? []
        for f in related {
            let fid = f.id
            context.delete(f)
            sync.enqueue(PendingChange(entity: "follows", recordId: fid, operation: .delete, updatedAt: .now))
        }
        // 既存ブロックが無ければ作成。
        let existing = (try? context.fetch(FetchDescriptor<Block>(predicate: #Predicate {
            $0.blockerId == blockerId && $0.blockedId == blockedId
        })))?.first
        if existing == nil {
            let block = Block(blockerId: blockerId, blockedId: blockedId, blockedDisplayName: displayName)
            context.insert(block)
            try? context.save()
            sync.enqueue(PendingChange(entity: "blocks", recordId: block.id, operation: .upsert, updatedAt: block.updatedAt))
        } else {
            try? context.save()
        }
    }

    /// ブロックを解除する。
    static func unblock(_ block: Block, context: ModelContext, sync: LocalSyncEngine) {
        let id = block.id
        context.delete(block)
        try? context.save()
        sync.enqueue(PendingChange(entity: "blocks", recordId: id, operation: .delete, updatedAt: .now))
    }

    /// 対象ユーザー/コンテンツを通報する。Report を作成し、サーバ `reports` へ送信（運営が確認）。
    static func report(reporterId: UUID, reportedUserId: UUID, reason: ModerationReason, detail: String?,
                       contextType: String?, contextId: UUID?,
                       context: ModelContext, sync: LocalSyncEngine) {
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let report = Report(reporterId: reporterId, reportedUserId: reportedUserId,
                            contextType: contextType, contextId: contextId,
                            reason: reason.rawValue, detail: (trimmed?.isEmpty == false) ? trimmed : nil)
        context.insert(report)
        try? context.save()
        sync.enqueue(PendingChange(entity: "reports", recordId: report.id, operation: .upsert, updatedAt: report.updatedAt))
    }
}

/// 通報シート提示用ターゲット（`sheet(item:)` 用）。
/// contextType/contextId を持たせると、ユーザー通報だけでなく投稿（feed_item）単位の通報にも使える。
struct ReportUserTarget: Identifiable {
    let id: UUID            // reportedUserId
    let displayName: String
    var contextType: String = "user"
    var contextId: UUID? = nil
}

/// 通報入力シート。理由を選び（任意で詳細）、送信すると運営に届く。
struct ReportSheet: View {
    let reporterId: UUID
    let reportedUserId: UUID
    let reportedDisplayName: String
    var contextType: String? = "user"
    var contextId: UUID?
    var onSubmitted: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ModerationReason = .inappropriate
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("理由") {
                    Picker("理由", selection: $reason) {
                        ForEach(ModerationReason.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("補足（任意）") {
                    TextField("具体的な内容", text: $detail, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    Text("通報内容は運営に送信され、確認のうえ対応します。\(reportedDisplayName) に通知されることはありません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("通報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("送信") {
                        Moderation.report(reporterId: reporterId, reportedUserId: reportedUserId,
                                          reason: reason, detail: detail,
                                          contextType: contextType, contextId: contextId,
                                          context: context, sync: sync)
                        onSubmitted?()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// ソーシャル初回利用時のコミュニティガイドライン同意ゲート（1.2.5）。
struct CommunityGuidelinesGate: View {
    var onAgree: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "person.2.badge.gearshape").font(.system(size: 44)).foregroundStyle(Theme.energy)
            Text("コミュニティのルール").font(.title2.bold())
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ruleRow("誹謗中傷・ハラスメント・スパムなど、不適切な投稿は禁止です。")
                ruleRow("不適切な投稿やユーザーは通報できます。運営が確認し対応します。")
                ruleRow("迷惑なユーザーはブロックできます。相手の投稿は表示されなくなります。")
            }
            .padding(.horizontal, Theme.Spacing.sm)
            Spacer()
            Button(action: onAgree) {
                Text("同意してはじめる").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).prominentLime().controlSize(.large)
            Text("「同意してはじめる」を押すと、利用規約とこのルールに同意したものとみなされます。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.lg)
        .multilineTextAlignment(.center)
    }

    private func ruleRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.energy)
            Text(text).font(.subheadline).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
