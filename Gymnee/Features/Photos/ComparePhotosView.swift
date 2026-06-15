import SwiftUI

/// 進捗写真の比較（§6.7 月次比較）。2 枚を並べて表示。既定は最古と最新。
struct ComparePhotosView: View {
    let photos: [ProgressPhoto]
    @Environment(\.dismiss) private var dismiss

    @State private var leftId: UUID?
    @State private var rightId: UUID?

    /// 表示は新しい順で渡される想定。
    private var sortedByDate: [ProgressPhoto] { photos.sorted { $0.date < $1.date } }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    comparePane(side: "Before", selection: $leftId)
                    comparePane(side: "After", selection: $rightId)
                }
                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .navigationTitle("ビフォー / アフター")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } }
            }
            .onAppear {
                leftId = leftId ?? sortedByDate.first?.id
                rightId = rightId ?? sortedByDate.last?.id
            }
        }
    }

    private func comparePane(side: String, selection: Binding<UUID?>) -> some View {
        let photo = photos.first { $0.id == selection.wrappedValue }
        return VStack(spacing: Theme.Spacing.sm) {
            Text(side).font(.caption.bold()).foregroundStyle(.secondary)
            if let photo, let image = PhotoStore.load(photo.localPhotoFilename) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(height: 360)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                Text(photo.date, format: .dateTime.year().month().day()).font(.caption2)
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.md).fill(.secondary.opacity(0.2)).frame(height: 360)
            }
            Menu {
                ForEach(sortedByDate) { p in
                    Button(p.date.formatted(date: .abbreviated, time: .omitted)) { selection.wrappedValue = p.id }
                }
            } label: {
                Label("日付を選択", systemImage: "calendar").font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
