import SwiftUI

/// サインイン・初期設定（§5 / §6.1）。
/// v0 はモック/ローカル認証。Sign in with Apple ボタンも用意するが実体はモックに委譲する。
struct OnboardingView: View {
    @Environment(AuthService.self) private var auth
    @State private var displayName: String = ""
    @State private var showNameEntry = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.deep, Theme.deep.opacity(0.85), Theme.energy.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(Theme.energy)
                    Text("Gymnee")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("カレンダーから始まる、\nクロスジムの筋トレ記録。")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }

                Spacer()

                featureRow(icon: "camera.fill", text: "写真チェックインで来店を記録")
                featureRow(icon: "chart.bar.fill", text: "セット・レップ・重量をフル記録")
                featureRow(icon: "flame.fill", text: "ヒートマップで継続を可視化")

                Spacer()

                VStack(spacing: Theme.Spacing.md) {
                    Button {
                        auth.signInWithApple()
                    } label: {
                        Label("Sign in with Apple", systemImage: "applelogo")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                            .foregroundStyle(.black)
                    }

                    Button {
                        showNameEntry = true
                    } label: {
                        Text("名前を入力して始める")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                            .foregroundStyle(.white)
                    }

                    Text("v0 はローカル認証で動作します（Sign in with Apple は後日有効化）。")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
        .sheet(isPresented: $showNameEntry) {
            nameEntrySheet
                .presentationDetents([.medium])
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.energy)
                .frame(width: 32)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameEntrySheet: some View {
        NavigationStack {
            Form {
                Section("表示名") {
                    TextField("例: たろう", text: $displayName)
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Button("始める") {
                        auth.signIn(displayName: displayName)
                        showNameEntry = false
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("プロフィール")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
