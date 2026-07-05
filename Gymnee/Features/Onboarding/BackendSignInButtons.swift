import SwiftUI
import AuthenticationServices

/// 後入れサインインのボタン群（ソーシャル・AI計画などのサインイン促しで共用）。
/// Apple / Google / メールの3経路。ゲスト期間のローカル記録は LocalDataMigrator が
/// サインイン時に新しい userId へ引き継ぐため、その旨の説明文を添える。
struct BackendSignInButtons: View {
    @Environment(AuthService.self) private var auth
    @State private var showEmailSignIn = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            SignInWithAppleButton(.signIn) { request in
                auth.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await auth.completeSignInWithApple(result) }
            }
            .signInWithAppleButtonStyle(.white)   // ダークファーストUIで視認できるのは白
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
        }
        .sheet(isPresented: $showEmailSignIn) {
            EmailSignInSheet()
        }
    }
}
