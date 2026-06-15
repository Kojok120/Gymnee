import SwiftUI

/// フィード 1 件のカード表示（§6.11）。来店は写真付き、PR/ワークアウトはサマリ。
struct FeedCardView: View {
    let entry: FeedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            if let photo = PhotoStore.load(entry.photoFilename) {
                Image(uiImage: photo)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            if let subtitle = entry.subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            if !entry.partners.isEmpty {
                Label(entry.partners.joined(separator: "・"), systemImage: "person.2.fill")
                    .font(.caption).foregroundStyle(Theme.energy)
            }
        }
        .gymneeCard()
    }

    private var header: some View {
        HStack {
            Image(systemName: entry.icon)
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.subheadline.bold())
                Text(entry.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Label(entry.visibility.label, systemImage: visibilityIcon)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var iconColor: Color {
        switch entry.kind {
        case .visit: return Theme.energy
        case .pr: return .yellow
        case .workout: return .orange
        }
    }

    private var visibilityIcon: String {
        switch entry.visibility {
        case .private: return "lock.fill"
        case .friends: return "person.2.fill"
        case .public: return "globe"
        }
    }
}
