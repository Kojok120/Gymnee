import SwiftUI

/// AI（MCP クライアント）の接続の承認（#171）。ブラウザの承認画面の QR / ボタンから開く。
///
/// ブラウザとこの画面に同じ番号を出し、利用者が見比べてから承認する（他人が始めた接続を承認させないため）。
/// 承認すると、ブラウザ側が自分で続きを進める。この画面は「元のアプリに戻ってください」で終わる。
struct ConnectApproveView: View {
    let pairingId: UUID

    @Environment(AuthService.self) private var auth
    @Environment(ConnectService.self) private var connect
    @Environment(\.dismiss) private var dismiss
    @State private var pairing: ConnectService.Pairing?
    @State private var errorMessage: String?
    @State private var allowWrite = true
    @State private var allowPropose = true
    @State private var isSending = false
    @State private var finished: Bool?

    var body: some View {
        NavigationStack {
            Form {
                if !(auth.isBackendAuthenticated || connect.isShowingFixture) {
                    Section {
                        Text("承認するには、先に設定 > アカウントからサインインしてください。")
                    }
                } else if let finished {
                    Section {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Label(finished ? "承認しました" : "拒否しました", systemImage: finished ? "checkmark.circle.fill" : "xmark.circle")
                                .font(.headline)
                                .foregroundStyle(finished ? Theme.textPrimary : .secondary)
                            Text(finished ? "接続を始めたアプリかブラウザに戻ってください。数秒で続きが進みます。" : "接続はされません。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                } else if let pairing {
                    content(pairing)
                } else if let errorMessage {
                    Section { Text(errorMessage) }
                } else {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .navigationTitle("AI の接続")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(finished == nil ? "閉じる" : "完了") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func content(_ p: ConnectService.Pairing) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(p.clientName).font(.title3.weight(.bold))
                if let domain = p.clientDomain {
                    Text("提供元: \(domain)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("名前はアプリの自己申告です").font(.caption).foregroundStyle(.secondary)
                }
                Text("権限を渡す先: \(p.redirectHost)").font(.caption).foregroundStyle(.secondary)
                if p.redirectIsLoopback {
                    Text("パソコンの中のアプリに権限を渡します。自分で接続を始めたときだけ承認してください。")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }

        Section {
            Text(p.code)
                .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                .frame(maxWidth: .infinity)
                .accessibilityLabel("確認の番号 \(p.code)")
        } header: {
            Text("ブラウザに同じ番号が出ていますか")
        } footer: {
            Text("番号が違う、または自分で接続を始めていないときは「拒否」を押してください。")
        }

        Section("できること") {
            ForEach(p.scopes, id: \.scope) { scope in
                switch scope.scope {
                case "workouts:write":
                    Toggle(scope.label, isOn: $allowWrite)
                case "coach:write":
                    Toggle(scope.label, isOn: $allowPropose)
                default:
                    Toggle(isOn: .constant(true)) { Text(scope.label) }.disabled(true)
                }
            }
        }

        Section {
            Button {
                Task { await decide(approve: true, pairing: p) }
            } label: {
                Text("承認する").frame(maxWidth: .infinity).font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSending)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            Button(role: .destructive) {
                Task { await decide(approve: false, pairing: p) }
            } label: {
                Text("拒否する").frame(maxWidth: .infinity)
            }
            .disabled(isSending)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func load() async {
        guard auth.isBackendAuthenticated || connect.isShowingFixture else { return }
        do {
            pairing = try await connect.pairing(id: pairingId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decide(approve: Bool, pairing p: ConnectService.Pairing) async {
        isSending = true
        defer { isSending = false }
        var scopes = ["read"]
        let requested = Set(p.scopes.map(\.scope))
        if requested.contains("workouts:write"), allowWrite { scopes.append("workouts:write") }
        if requested.contains("coach:write"), allowPropose { scopes.append("coach:write") }
        do {
            try await connect.decide(pairingId: pairingId, approve: approve, scopes: scopes)
            finished = approve
        } catch {
            errorMessage = error.localizedDescription
            pairing = nil
        }
    }
}
