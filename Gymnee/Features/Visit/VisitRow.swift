import SwiftUI

/// 来店 1 件の行表示（写真サムネ＋ジム名＋時刻＋メモ＋合トレ）。日別詳細・ジム詳細で共用。
struct VisitRow: View {
    let visit: Visit

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.gym?.name ?? "ジム未設定")
                    .font(.subheadline.bold())
                Text(visit.visitedAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = visit.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if !visit.partners.isEmpty {
                    Label("\(visit.partners.count)人と合トレ", systemImage: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.energy)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = PhotoStore.load(visit.localPhotoFilename) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.energy.opacity(0.15))
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(Theme.energy))
        }
    }
}
