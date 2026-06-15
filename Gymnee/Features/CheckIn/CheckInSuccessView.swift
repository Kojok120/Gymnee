import SwiftUI

/// チェックイン保存後の確認＋共有導線（§6.3 末尾）。共有カード生成は P3 で実装する。
struct CheckInSuccessView: View {
    let visit: Visit
    var onDone: () -> Void

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
                    // P3: 共有カード生成へ。
                } label: {
                    Label("共有カードを作成", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.energy)
                .disabled(true)
                .overlay(alignment: .trailing) {
                    Text("P3").font(.caption2).foregroundStyle(.secondary).padding(.trailing, 8)
                }

                Button("完了", action: onDone)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .navigationBarBackButtonHidden()
    }
}
