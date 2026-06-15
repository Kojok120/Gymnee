import SwiftUI

/// 進捗写真の比較（§6.7 月次比較）。スライダー式ビフォーアフター。既定は最古と最新。
struct ComparePhotosView: View {
    let photos: [ProgressPhoto]
    @Environment(\.dismiss) private var dismiss

    @State private var beforeId: UUID?
    @State private var afterId: UUID?

    private var sortedByDate: [ProgressPhoto] { photos.sorted { $0.date < $1.date } }
    private var before: ProgressPhoto? { photos.first { $0.id == beforeId } }
    private var after: ProgressPhoto? { photos.first { $0.id == afterId } }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                SliderCompare(
                    beforeImage: PhotoStore.load(before?.localPhotoFilename),
                    afterImage: PhotoStore.load(after?.localPhotoFilename)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))

                HStack {
                    datePicker(title: "Before", selection: $beforeId, photo: before)
                    Spacer()
                    datePicker(title: "After", selection: $afterId, photo: after)
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
                beforeId = beforeId ?? sortedByDate.first?.id
                afterId = afterId ?? sortedByDate.last?.id
            }
        }
    }

    private func datePicker(title: String, selection: Binding<UUID?>, photo: ProgressPhoto?) -> some View {
        Menu {
            ForEach(sortedByDate) { p in
                Button(p.date.formatted(date: .abbreviated, time: .omitted)) { selection.wrappedValue = p.id }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Label(photo?.date.formatted(date: .abbreviated, time: .omitted) ?? "選択", systemImage: "calendar")
                    .font(.caption)
            }
        }
    }
}

/// 2 枚を縦の境界線で重ね、ドラッグで境界を動かすスライダー比較。
private struct SliderCompare: View {
    let beforeImage: UIImage?
    let afterImage: UIImage?
    @State private var fraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .leading) {
                imageView(beforeImage, w: w, h: h)
                imageView(afterImage, w: w, h: h)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: w * fraction)
                    }
                // 境界線＋ハンドル
                ZStack {
                    Rectangle().fill(.white).frame(width: 2)
                    Image(systemName: "arrow.left.and.right.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
                .position(x: w * fraction, y: h / 2)

                labelTag("Before", align: .leading)
                labelTag("After", align: .trailing)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    fraction = min(max(value.location.x / w, 0), 1)
                }
            )
        }
    }

    @ViewBuilder
    private func imageView(_ image: UIImage?, w: CGFloat, h: CGFloat) -> some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill().frame(width: w, height: h).clipped()
        } else {
            Rectangle().fill(.secondary.opacity(0.2)).frame(width: w, height: h)
                .overlay(Text("写真を選択").font(.caption).foregroundStyle(.secondary))
        }
    }

    private func labelTag(_ text: String, align: Alignment) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.5), in: Capsule())
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align == .leading ? .topLeading : .topTrailing)
    }
}
