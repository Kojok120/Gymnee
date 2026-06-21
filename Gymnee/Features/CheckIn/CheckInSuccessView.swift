import SwiftUI
import SwiftData

/// チェックイン保存後の確認＋共有導線（§6.3 末尾 / §6.6）。アプリの祝祭モーメント。
struct CheckInSuccessView: View {
    let visit: Visit
    var onDone: () -> Void

    @Query private var visits: [Visit]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showShare = false
    @State private var appeared = false

    init(visit: Visit, onDone: @escaping () -> Void) {
        self.visit = visit
        self.onDone = onDone
        let userId = visit.userId
        _visits = Query(filter: #Predicate<Visit> { $0.userId == userId })
    }

    private var streak: Int {
        StreakCalculator.currentStreak(visitDays: visits.map(\.visitedAt))
    }

    var body: some View {
        ZStack {
            Theme.bg0.ignoresSafeArea()
            // 背後の lime グロー（祝祭感）。
            Circle()
                .fill(Theme.lime.opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 100)
                .offset(y: -180)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Theme.limeSoft)
                        .frame(width: 132, height: 132)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 84))
                        .foregroundStyle(Theme.lime)
                        .symbolEffect(.bounce, value: appeared)
                }
                .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                .opacity(appeared || reduceMotion ? 1 : 0)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("チェックイン完了！")
                        .font(.title.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text(visit.gym?.name ?? "ジム")
                        .font(.headline)
                        .foregroundStyle(Theme.textSecondary)
                    if streak > 0 {
                        Label("\(streak)日連続！", systemImage: "flame.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.warning)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 6)
                            .background(Theme.warning.opacity(0.15), in: Capsule())
                            .padding(.top, 2)
                    }
                }
                .opacity(appeared || reduceMotion ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 12)

                if let image = PhotoStore.load(visit.localPhotoFilename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.top, Theme.Spacing.sm)
                }

                Spacer()

                VStack(spacing: Theme.Spacing.md) {
                    Button { showShare = true } label: {
                        Label("共有カードを作成", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.gymneePrimary)

                    Button("完了", action: onDone)
                        .buttonStyle(.gymneeSecondary)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .navigationBarBackButtonHidden()
        .sensoryFeedback(.success, trigger: appeared)
        .task {
            withAnimation(.bouncy) { appeared = true }
        }
        .sheet(isPresented: $showShare) {
            ShareCardEditorView(content: .from(visit: visit, streak: streak, prText: nil))
        }
    }
}
