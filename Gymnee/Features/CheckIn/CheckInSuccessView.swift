import SwiftUI
import SwiftData

/// チェックイン保存後の確認＋共有導線（§6.3 末尾 / §6.6）。共有カード生成を起動する。
struct CheckInSuccessView: View {
    let visit: Visit
    var onDone: () -> Void

    @Query private var visits: [Visit]
    @State private var showShare = false

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
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.energy)
            Text("チェックイン完了！")
                .font(.title2.bold())
            Text(visit.gym?.name ?? "ジム")
                .font(.headline)
                .foregroundStyle(.secondary)
            if streak > 0 {
                Label("\(streak)日連続！", systemImage: "flame.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }

            if let image = PhotoStore.load(visit.localPhotoFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                    .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                Button {
                    showShare = true
                } label: {
                    Label("共有カードを作成", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.energy)

                Button("完了", action: onDone)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $showShare) {
            ShareCardEditorView(content: .from(visit: visit, streak: streak, prText: nil))
        }
    }
}
