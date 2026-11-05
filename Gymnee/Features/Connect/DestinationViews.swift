import SwiftUI
import AuthenticationServices

/// 連携の「Slack・Discord」の節（#171 の 2 段目）。
///
/// 基本は「追加」ボタン（OAuth でチャンネルを選ぶだけ）。URL を貼るのは上級者向けの別の入口にする。
struct DestinationSection: View {
    @Environment(ConnectService.self) private var connect
    @Environment(AppErrorCenter.self) private var errors
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var showPasteSheet = false
    @State private var editing: ConnectService.Destination?
    @State private var connectingProvider: String?
    @State private var resultMessage: String?

    var body: some View {
        Section {
            ForEach(connect.connections?.destinations ?? []) { destination in
                Button { editing = destination } label: { row(destination) }
                    .buttonStyle(.plain)
            }
            if let providers = connect.connections?.providers {
                if providers.slack {
                    addButton(title: "Slack に追加", provider: "slack", systemImage: "number")
                }
                if providers.discord {
                    addButton(title: "Discord に追加", provider: "discord", systemImage: "bubble.left.and.bubble.right")
                }
            }
            Button { showPasteSheet = true } label: {
                Label("URL を貼って追加（Webhook）", systemImage: "link")
            }
            if let resultMessage {
                Text(resultMessage).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Slack・Discord")
        } footer: {
            Text("記録を終えたときと、月曜の朝に先週のふりかえりを、選んだチャンネルにお知らせします。")
        }
        .sheet(isPresented: $showPasteSheet) { AddDestinationURLSheet() }
        .sheet(item: $editing) { DestinationDetailSheet(destination: $0) }
    }

    private func row(_ d: ConnectService.Destination) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(d.kindLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.connect.opacity(0.15), in: Capsule())
                    Text(d.label).font(.body.weight(.semibold)).lineLimit(1)
                }
                Text(Self.eventsSummary(d.events)).font(.caption).foregroundStyle(.secondary)
                if let reason = d.disabledReason {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func addButton(title: String, provider: String, systemImage: String) -> some View {
        Button {
            Task { await connectChat(provider) }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                if connectingProvider == provider { Spacer(); ProgressView() }
            }
        }
        .disabled(connectingProvider != nil)
    }

    /// 「追加」ボタン: Slack / Discord の画面でチャンネルを選んでもらい、gymnee:// で戻ってくる。
    private func connectChat(_ provider: String) async {
        connectingProvider = provider
        defer { connectingProvider = nil }
        do {
            let start = try await connect.chatConnectURL(provider: provider)
            let callback = try await webAuthenticationSession.authenticate(using: start.url, callbackURLScheme: start.callbackScheme)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if items.first(where: { $0.name == "status" })?.value == "ok" {
                resultMessage = "つながりました。チャンネルに確かめのメッセージを送りました。"
            } else {
                resultMessage = items.first(where: { $0.name == "message" })?.value ?? "つなげませんでした。"
            }
            await connect.load()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // 利用者が閉じた。何も出さない。
        } catch {
            errors.report(error.localizedDescription)
        }
    }

    static func eventsSummary(_ events: [String]) -> String {
        var parts: [String] = []
        if events.contains(ConnectService.Destination.workoutCompleted) { parts.append("記録したとき") }
        if events.contains(ConnectService.Destination.weeklySummary) { parts.append("週のふりかえり") }
        return parts.isEmpty ? "何も送らない" : parts.joined(separator: "・")
    }
}

/// 送り先 1 つの設定（送る内容・止まったときの再開・削除）。
struct DestinationDetailSheet: View {
    let destination: ConnectService.Destination

    @Environment(ConnectService.self) private var connect
    @Environment(\.dismiss) private var dismiss
    @State private var onWorkout: Bool
    @State private var onWeekly: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    init(destination: ConnectService.Destination) {
        self.destination = destination
        _onWorkout = State(initialValue: destination.events.contains(ConnectService.Destination.workoutCompleted))
        _onWeekly = State(initialValue: destination.events.contains(ConnectService.Destination.weeklySummary))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("送り先", value: destination.label)
                    LabeledContent("種類", value: destination.kindLabel)
                    if let last = destination.lastDeliveredAt {
                        LabeledContent("最後に届いた日", value: ConnectionsView.day(last))
                    }
                }
                if let reason = destination.disabledReason {
                    Section {
                        Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                        Button("もう一度試す") { Task { await resume() } }.disabled(isSaving)
                    } footer: {
                        Text("確かめのメッセージが届けば、また送り始めます。")
                    }
                }
                Section("送る内容") {
                    Toggle("記録を終えたとき", isOn: $onWorkout)
                    Toggle("月曜の朝に先週のふりかえり", isOn: $onWeekly)
                }
                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(Theme.danger) }
                }
                Section {
                    Button("この送り先を消す", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(destination.kindLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving || (!onWorkout && !onWeekly) || !changed)
                }
            }
            .confirmationDialog("この送り先を消しますか", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("消す", role: .destructive) { Task { await delete() } }
            } message: {
                Text("\(destination.label) には、もう何も送りません。")
            }
        }
    }

    private var events: [String] {
        var out: [String] = []
        if onWorkout { out.append(ConnectService.Destination.workoutCompleted) }
        if onWeekly { out.append(ConnectService.Destination.weeklySummary) }
        return out
    }

    private var changed: Bool { Set(events) != Set(destination.events) }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await connect.updateDestination(id: destination.id, events: events)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func resume() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await connect.resumeDestination(id: destination.id)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func delete() async {
        do {
            try await connect.deleteDestination(id: destination.id)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

/// URL を貼って足す（Slack / Discord の Webhook の URL、または自分のサーバー）。
struct AddDestinationURLSheet: View {
    @Environment(ConnectService.self) private var connect
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var url = ""
    @State private var label = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var created: ConnectService.CreatedDestination?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    Section {
                        Label("つながりました。確かめのメッセージを送りました。", systemImage: "checkmark.circle.fill")
                    }
                    if let secret = created.signingSecret {
                        Section {
                            Text(secret).font(.callout.monospaced()).textSelection(.enabled)
                            Button {
                                UIPasteboard.general.string = secret
                                copied = true
                            } label: {
                                Label(copied ? "コピーした" : "署名の鍵をコピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .sensoryFeedback(.success, trigger: copied)
                        } header: {
                            Text("署名の鍵")
                        } footer: {
                            Text("受け取る側で、Gymnee から届いたことを確かめるのに使います（Standard Webhooks）。この画面を閉じると二度と表示されません。")
                        }
                    }
                } else {
                    Section {
                        TextField("https://hooks.slack.com/services/…", text: $url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("名前（例: 筋トレ部）", text: $label)
                    } footer: {
                        Text("Slack の Incoming Webhook・Discord の Webhook・自分のサーバーの https の URL を貼れます。")
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).font(.footnote).foregroundStyle(Theme.danger) }
                    }
                    Section {
                        Button { openURL(URL(string: "https://gymnee.app/connect/chat/")!) } label: {
                            Label("URL の取り方", systemImage: "questionmark.circle")
                        }
                    }
                }
            }
            .navigationTitle("URL を貼って追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(created == nil ? "キャンセル" : "閉じる") { dismiss() }
                }
                if created == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("追加") { Task { await add() } }
                            .disabled(isSending || url.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(created?.signingSecret != nil && !copied)
        }
    }

    private func add() async {
        isSending = true
        defer { isSending = false }
        do {
            created = try await connect.addDestination(
                url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                label: label.trimmingCharacters(in: .whitespaces)
            )
            errorMessage = nil
            if created?.signingSecret == nil { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
