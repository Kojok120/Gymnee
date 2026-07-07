import SwiftUI
import AuthenticationServices

/// 後入れサインインのボタン群（ソーシャル・AI計画などのサインイン促しで共用）。
/// Apple / Google / メールの3経路。ゲスト期間のローカル記録は LocalDataMigrator が
/// サインイン時に新しい userId へ引き継ぐため、その旨の説明文を添える。
struct BackendSignInButtons: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    @State private var showEmailSignIn = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            SignInWithAppleButton(.signIn) { request in
                auth.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await auth.completeSignInWithApple(result) }
            }
            // このボタンはシステム背景のシート上に出る。ライト背景では白ボタンが埋もれて
            // 「ボタンと分からない」ため、背景に合わせて配色を反転する（App Store ガイドライン4）。
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

            if auth.isBackendAvailable {
                Button {
                    Task { await auth.signInWithGoogle() }
                } label: {
                    Label("Google で続ける", systemImage: "globe")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.bordered)

                Button {
                    showEmailSignIn = true
                } label: {
                    Label("メールで続ける", systemImage: "envelope.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.bordered)
            }

            Text("これまでにこの端末で記録したデータは、そのまま引き継がれます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // 登録・ログイン前に EULA / 利用規約を提示（App Store ガイドライン1.2）。
            LegalAgreementFooter(appearance: .adaptive)
        }
        .sheet(isPresented: $showEmailSignIn) {
            EmailSignInSheet()
        }
    }
}
