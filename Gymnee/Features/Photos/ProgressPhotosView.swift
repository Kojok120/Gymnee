import SwiftUI
import SwiftData

/// 進捗写真（§6.7）。来店写真と別枠、既定 private、月次比較タイムライン。
struct ProgressPhotosView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Query private var photos: [ProgressPhoto]
    @State private var showAdd = false
    @State private var showCompare = false
    @State private var fullscreen: ProgressPhoto?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 6)]

    init(userId: UUID) {
        self.userId = userId
        _photos = Query(
            filter: #Predicate<ProgressPhoto> { $0.userId == userId },
            sort: \ProgressPhoto.date, order: .reverse
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg, pinnedViews: [.sectionHeaders]) {
                ForEach(monthKeys, id: \.self) { key in
                    Section {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(grouped[key] ?? []) { photo in
                                thumb(photo)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                    } header: {
                        Text(key)
                            .font(.headline)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.bar)
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .overlay {
            if photos.isEmpty {
                EmptyStateView(systemImage: "photo.stack", title: "進捗写真がありません", message: "右上の＋で体型写真を追加（既定は非公開）。")
            }
        }
        .navigationTitle("進捗写真")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCompare = true } label: { Image(systemName: "rectangle.split.2x1") }
                    .disabled(photos.count < 2)
            }
        }
        .sheet(isPresented: $showAdd) { AddProgressPhotoView(userId: userId) }
        .sheet(isPresented: $showCompare) { ComparePhotosView(photos: photos) }
        .sheet(item: $fullscreen) { photo in
            photoFullscreen(photo)
        }
    }

    private func thumb(_ photo: ProgressPhoto) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = PhotoStore.load(photo.localPhotoFilename) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 110, height: 140)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(.secondary.opacity(0.2)).frame(width: 110, height: 140)
            }
            if photo.visibility == .private {
                Image(systemName: "lock.fill")
                    .font(.caption2).padding(4)
                    .background(.black.opacity(0.5), in: Circle())
                    .foregroundStyle(.white).padding(4)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text(photo.date, format: .dateTime.month().day())
                .font(.caption2.bold())
                .padding(4).background(.black.opacity(0.5), in: Capsule())
                .foregroundStyle(.white).padding(4)
        }
        .onTapGesture { fullscreen = photo }
    }

    private func photoFullscreen(_ photo: ProgressPhoto) -> some View {
        NavigationStack {
            VStack {
                if let image = PhotoStore.load(photo.localPhotoFilename) {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            }
            .navigationTitle(photo.date.formatted(date: .abbreviated, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("削除", role: .destructive) {
                        let photoId = photo.id
                        PhotoStore.delete(photo.localPhotoFilename)
                        context.delete(photo)
                        try? context.save()
                        sync.enqueue(PendingChange(entity: "progress_photos", recordId: photoId, operation: .delete, updatedAt: .now))
                        fullscreen = nil
                    }
                }
            }
        }
    }

    private var grouped: [String: [ProgressPhoto]] {
        Dictionary(grouping: photos, by: monthKey)
    }
    private var monthKeys: [String] {
        grouped.keys.sorted(by: >)
    }
    private func monthKey(_ photo: ProgressPhoto) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年 M月"
        return f.string(from: photo.date)
    }
}
