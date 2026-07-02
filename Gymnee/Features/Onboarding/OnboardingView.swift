import SwiftUI
import AuthenticationServices

/// サインイン・初期設定（§5 / §6.1）。アプリの第一印象。
/// Sign in with Apple / Google / メールでアカウント作成（オフライン/ゲスト開始は廃止）。
/// アカウント必須にすることで、サインイン方法の違いによる多重ID・孤児データの発生を防ぐ。
struct OnboardingView: View {
    @Environment(AuthService.self) private var auth
    @State private var showEmailSignIn = false
    @State private var appeared = false

    /// 特徴はタイトルのみ（説明文は画面高が足りない端末で途切れ、情報過多だったため廃止）。
    private let features: [(icon: String, title: String)] = [
        ("door.right.hand.open", "写真でチェックイン"),
        ("dumbbell.fill", "セット・レップ・重量をフル記録"),
        ("flame.fill", "ヒートマップで継続を可視化")
    ]

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                Spacer(minLength: Theme.Spacing.xxl)
                hero
                Spacer(minLength: Theme.Spacing.xl)
                featureList
                Spacer(minLength: Theme.Spacing.xl)
                actions
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .sheet(isPresented: $showEmailSignIn) {
            EmailSignInSheet()
        }
        .task {
            withAnimation(.smooth.delay(0.05)) { appeared = true }
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            Theme.heroBackground.ignoresSafeArea()
            // ふわりと浮かぶ lime のグロー（奥行き）。
            Circle()
                .fill(Theme.lime.opacity(0.22))
                .frame(width: 360, height: 360)
                .blur(radius: 120)
                .offset(x: 120, y: -260)
                .ignoresSafeArea()
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Theme.lime.opacity(0.16))
                    .frame(width: 108, height: 108)
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Theme.limeFill)
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Gymnee")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("カレンダーから始まる、筋トレ記録。")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)   // 画面高が足りない端末でも途切れさせない
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
    }

    // MARK: - Feature list

    private var featureList: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(Array(features.enumerated()), id: \.offset) { index, f in
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: f.icon)
                        .font(.title3)
                        .foregroundStyle(Theme.limeFill)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    Text(f.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                .animation(.smooth.delay(0.12 + Double(index) * 0.08), value: appeared)
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: Theme.Spacing.md) {
            SignInWithAppleButton(.signIn) { request in
                auth.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await auth.completeSignInWithApple(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

            if auth.isBackendAvailable {
                providerButton(title: "Google で続ける", systemImage: "globe") {
                    Task { await auth.signInWithGoogle() }
                }
                providerButton(title: "メールで続ける", systemImage: "envelope.fill") {
                    showEmailSignIn = true
                }
            }

            Text("サインインすると、複数端末での同期・通知・フレンド機能が使えます。")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.smooth.delay(0.36), value: appeared)
    }

    /// Onboarding のダーク背景に合うサインインボタン（半透明白）。
    private func providerButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
                .foregroundStyle(.white)
        }
    }
}
