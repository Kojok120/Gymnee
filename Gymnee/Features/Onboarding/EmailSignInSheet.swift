import SwiftUI

/// メール OTP サインイン（§6.1）。メール入力 → 6桁コード送信 → コード検証の2段。
/// マジックリンク（ディープリンク）ではなくコード方式で、Onboarding / Settings から再利用する。
struct EmailSignInSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    var onSignedIn: () -> Void = {}

    @State private var email = ""
    @State private var code = ""
    @State private var stage: Stage = .enterEmail
    @State private var busy = false
    @State private var error: String?

    enum Stage { case enterEmail, enterCode }

    var body: some View {
        NavigationStack {
            Form {
                switch stage {
                case .enterEmail:
                    Section {
                        TextField("メールアドレス", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("入力したメールに6桁の確認コードを送ります。")
                    }
                    Section {
                        Button(busy ? "送信中…" : "コードを送る") { Task { await send() } }
                            .disabled(busy || !isValidEmail)
                    }
                case .enterCode:
                    Section {
                        TextField("6桁コード", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    } header: {
                        Text("\(email) に届いたコード")
                    }
                    Section {
                        Button(busy ? "確認中…" : "サインイン") { Task { await verify() } }
                            .disabled(busy || code.trimmingCharacters(in: .whitespaces).count < 6)
                        Button("メールを入れ直す") {
                            stage = .enterEmail; code = ""; error = nil
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("メールで続ける")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
            }
        }
    }

    private var isValidEmail: Bool {
        let t = email.trimmingCharacters(in: .whitespaces)
        return t.contains("@") && t.contains(".") && !t.hasSuffix("@")
    }

    private func send() async {
        busy = true; error = nil
        defer { busy = false }
        if await auth.sendEmailCode(email) {
            stage = .enterCode
        } else {
            error = "コードを送れませんでした。メールアドレスと通信状況を確認してください。"
        }
    }

    private func verify() async {
        busy = true; error = nil
        defer { busy = false }
        if await auth.verifyEmailCode(email: email, code: code) {
            onSignedIn()
            dismiss()
        } else {
            error = "コードが正しくありません。期限切れの場合は送り直してください。"
        }
    }
}
