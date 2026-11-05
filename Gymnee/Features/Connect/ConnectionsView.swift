import SwiftUI

/// その他 > 連携（#171）。Gymnee をアプリの外の道具とつなぐ入口。
///
/// いまは AI（Claude・ChatGPT など。MCP）と API キーの 2 つ。LINE と Slack / Discord はこの画面に足していく。
/// 説明の段落は置かず、やり方の詳細は「使い方」（gymnee.app/connect）に任せる。
struct ConnectionsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(ConnectService.self) private var connect
    @Environment(AppErrorCenter.self) private var errors
    @Environment(\.openURL) private var openURL
    @State private var showCreateToken = false
    @State private var copiedMcpUrl = false
    @State private var revokeTarget: RevokeTarget?

    private enum RevokeTarget: Identifiable {
        case ai(ConnectService.AIClient)
        case token(ConnectService.ApiToken)
        var id: String {
            switch self {
            case let .ai(c): return "ai-\(c.id)"
            case let .token(t): return "token-\(t.id)"
            }
        }
        var title: String {
            switch self {
            case let .ai(c): return "\(c.name) の接続を解除しますか"
            case let .token(t): return "API キー「\(t.name)」を消しますか"
            }
        }
        var message: String {
            switch self {
            case .ai: return "その AI からは、もう記録を読めなくなります。"
            case .token: return "このキーを使っているスクリプトや AI は、すぐに動かなくなります。"
            }
        }
    }

    private static let docsURL = URL(string: "https://gymnee.app/connect/")!

    var body: some View {
        Form {
            if !(auth.isBackendAuthenticated || connect.isShowingFixture) {
                Section {
                    Label("連携を使うには、設定 > アカウントからサインインしてください。", systemImage: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
            } else {
                aiSection
                apiSection
                if let message = connect.loadError {
                    Section { Text(message).font(.footnote).foregroundStyle(Theme.danger) }
                }
            }
            Section {
                Button { openURL(Self.docsURL) } label: {
                    Label("使い方とレシピ", systemImage: "book")
                }
            }
        }
        .navigationTitle("連携")
        .navigationBarTitleDisplayMode(.inline)
        .task { if auth.isBackendAuthenticated { await connect.load() } }
        .refreshable { await connect.load() }
        .sheet(isPresented: $showCreateToken) { ApiTokenCreateSheet() }
        .confirmationDialog(revokeTarget?.title ?? "", isPresented: Binding(get: { revokeTarget != nil }, set: { if !$0 { revokeTarget = nil } }), titleVisibility: .visible) {
            Button(revokeTarget.map { if case .ai = $0 { return "解除する" } else { return "消す" } } ?? "", role: .destructive) {
                guard let target = revokeTarget else { return }
                Task { await revoke(target) }
            }
        } message: {
            Text(revokeTarget?.message ?? "")
        }
    }

    // MARK: - AI（MCP）

    private var aiSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Claude や ChatGPT に、この URL を追加するだけでつながります。承認はこのアプリで行います。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(connect.connections?.mcpUrl ?? "https://api.gymnee.app/mcp")
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = connect.connections?.mcpUrl ?? "https://api.gymnee.app/mcp"
                        copiedMcpUrl = true
                    } label: {
                        Label(copiedMcpUrl ? "コピーした" : "コピー", systemImage: copiedMcpUrl ? "checkmark" : "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .sensoryFeedback(.success, trigger: copiedMcpUrl)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)

            if let clients = connect.connections?.aiClients, !clients.isEmpty {
                ForEach(clients) { client in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.name).font(.body.weight(.semibold))
                        Text(client.scopes.map(\.label).joined(separator: " / "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("つないだ日: \(Self.day(client.createdAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("解除", role: .destructive) { revokeTarget = .ai(client) }
                    }
                    .contextMenu {
                        Button("解除", systemImage: "link.badge.minus", role: .destructive) { revokeTarget = .ai(client) }
                    }
                }
            } else if connect.connections != nil {
                Text("つないでいる AI はまだありません。").font(.footnote).foregroundStyle(.secondary)
            } else if connect.isLoading {
                ProgressView()
            }
        } header: {
            Text("AI（Claude・ChatGPT など）")
        }
    }

    // MARK: - API キー

    private var apiSection: some View {
        Section {
            if let tokens = connect.connections?.apiTokens, !tokens.isEmpty {
                ForEach(tokens) { token in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(token.name).font(.body.weight(.semibold))
                            Spacer()
                            Text("\(token.prefix)…").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Text(token.scopes.map(\.label).joined(separator: " / "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(token.lastUsedAt.map { "最後に使った日: \(Self.day($0))" } ?? "まだ使われていません")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("消す", role: .destructive) { revokeTarget = .token(token) }
                    }
                    .contextMenu {
                        Button("消す", systemImage: "trash", role: .destructive) { revokeTarget = .token(token) }
                    }
                }
            }
            Button {
                showCreateToken = true
            } label: {
                Label("API キーを作る", systemImage: "key")
            }
        } header: {
            Text("API キー（開発者・Claude Code 向け）")
        } footer: {
            Text("自分で書いたスクリプトや Claude Code から使います。キーはパスワードと同じように扱ってください。")
        }
    }

    // MARK: - 操作

    private func revoke(_ target: RevokeTarget) async {
        revokeTarget = nil
        do {
            switch target {
            case let .ai(client): try await connect.revokeAIClient(id: client.id)
            case let .token(token): try await connect.revokeToken(id: token.id)
            }
        } catch {
            errors.report(error.localizedDescription)
        }
    }

    /// サーバーの ISO 8601 を「11月5日」にする。
    static func day(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "—" }
        return date.formatted(.dateTime.month().day())
    }
}

/// API キーを作るシート。作った直後に 1 回だけキーを見せる。
struct ApiTokenCreateSheet: View {
    @Environment(ConnectService.self) private var connect
    @Environment(\.dismiss) private var dismiss
    @State private var name = "マイスクリプト"
    @State private var canWrite = false
    @State private var canPropose = false
    @State private var isCreating = false
    @State private var created: ConnectService.CreatedToken?
    @State private var errorMessage: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    Section {
                        Text(created.token)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = created.token
                            copied = true
                        } label: {
                            Label(copied ? "コピーした" : "キーをコピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .sensoryFeedback(.success, trigger: copied)
                    } header: {
                        Text(created.name)
                    } footer: {
                        Text("この画面を閉じると、キーは二度と表示されません。なくしたら消して作り直してください。")
                    }
                } else {
                    Section("名前") {
                        TextField("例: 自宅の Mac", text: $name)
                    }
                    Section {
                        Toggle(isOn: .constant(true)) { Text("記録を読む") }.disabled(true)
                        Toggle("記録を足す", isOn: $canWrite)
                        Toggle("コーチにメニューを提案する", isOn: $canPropose)
                    } header: {
                        Text("できること")
                    } footer: {
                        Text("消す・直すは、どのキーでもできません（アプリだけで行います）。")
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).font(.footnote).foregroundStyle(Theme.danger) }
                    }
                }
            }
            .navigationTitle(created == nil ? "API キーを作る" : "API キーができました")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(created == nil ? "キャンセル" : "閉じる") { dismiss() }
                }
                if created == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("作る") { Task { await create() } }
                            .disabled(isCreating || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(created != nil && !copied)
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        var scopes = ["read"]
        if canWrite { scopes.append("workouts:write") }
        if canPropose { scopes.append("coach:write") }
        do {
            created = try await connect.createToken(name: name.trimmingCharacters(in: .whitespaces), scopes: scopes)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
