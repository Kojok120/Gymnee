import SwiftUI

/// 連携の「LINE」の節（#171 の 3 段目）。AI に詳しくない人向けの入口なので、連携の画面のいちばん上に置く。
///
/// 連携は LINE ログインを使わない。ボタンで LINE が開き、「連携 123456」が入った状態のトークを送るだけ。
/// 送ったあとアプリに戻ると、自動で連携の状態を読み直す。
struct LineSection: View {
    @Environment(ConnectService.self) private var connect
    @Environment(AppErrorCenter.self) private var errors
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var linkCode: ConnectService.LinkCode?
    @State private var isWorking = false
    @State private var confirmUnlink = false

    var body: some View {
        if let line = connect.connections?.line, line.configured {
            Section {
                if line.linked {
                    linkedRows(line)
                } else {
                    unlinkedRows
                }
            } header: {
                Text("LINE")
            } footer: {
                Text(line.linked
                     ? "LINE で話しかけると、コーチがあなたの記録を見て答えます。「ベンチ 60kg 10回 3セット」と送れば記録もできます。"
                     : "LINE で話しかけるだけで、記録とコーチ。毎朝のメニューも届きます。")
            }
            .onChange(of: scenePhase) { _, phase in
                // LINE で連携コードを送って戻ってきたら、連携できたかを読み直す。
                if phase == .active, linkCode != nil { Task { await connect.load() } }
            }
            .onChange(of: line.linked) { _, linked in if linked { linkCode = nil } }
            .confirmationDialog("LINE との連携を解除しますか", isPresented: $confirmUnlink, titleVisibility: .visible) {
                Button("解除する", role: .destructive) { Task { await unlink() } }
            } message: {
                Text("LINE からの記録・コーチ・通知が止まります。あとで連携し直せます。")
            }
        }
    }

    @ViewBuilder
    private var unlinkedRows: some View {
        Button {
            Task { await startLink() }
        } label: {
            HStack {
                Label("LINE と連携", systemImage: "message.fill")
                if isWorking { Spacer(); ProgressView() }
            }
        }
        .disabled(isWorking)
        if let linkCode {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("LINE で「連携 \(linkCode.code)」を送ってください。")
                    .font(.callout.weight(.semibold))
                Text("LINE が開かないときは、Gymnee の公式アカウントを友だちに追加してから、もう一度押してください。コードは 10 分で切れます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, Theme.Spacing.xs)
            Button("公式アカウントを友だちに追加") {
                if let url = URL(string: linkCode.addFriendUrl) { openURL(url) }
            }
            Button("連携できたか確かめる") { Task { await connect.load() } }
        }
    }

    @ViewBuilder
    private func linkedRows(_ line: ConnectService.Line) -> some View {
        Label("連携しています", systemImage: "checkmark.circle.fill")
        Picker("通知", selection: Binding(
            get: { ConnectService.LineNotifyMode(rawValue: line.notifyMode ?? "daily") ?? .daily },
            set: { mode in Task { await update(mode: mode) } }
        )) {
            ForEach(ConnectService.LineNotifyMode.allCases) { Text($0.label).tag($0) }
        }
        if (line.notifyMode ?? "daily") != ConnectService.LineNotifyMode.off.rawValue {
            Picker("時刻", selection: Binding(
                get: { line.notifyHour ?? 7 },
                set: { hour in Task { await update(hour: hour) } }
            )) {
                ForEach(5...22, id: \.self) { Text("\($0) 時").tag($0) }
            }
        }
        if let url = line.addFriendUrl.flatMap(URL.init(string:)) {
            Button("LINE を開く") { openURL(url) }
        }
        Button("連携を解除", role: .destructive) { confirmUnlink = true }
    }

    private func startLink() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let code = try await connect.lineLinkCode()
            linkCode = code
            if let url = URL(string: code.openUrl) { openURL(url) }
        } catch {
            errors.report(error.localizedDescription)
        }
    }

    private func update(mode: ConnectService.LineNotifyMode? = nil, hour: Int? = nil) async {
        do { try await connect.updateLine(mode: mode, hour: hour) } catch { errors.report(error.localizedDescription) }
    }

    private func unlink() async {
        do { try await connect.unlinkLine() } catch { errors.report(error.localizedDescription) }
    }
}
