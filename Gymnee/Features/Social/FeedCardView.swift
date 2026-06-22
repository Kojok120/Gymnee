import SwiftUI

/// フィード 1 件のカード表示（§6.11）。来店は写真付き、PR/ワークアウトはサマリ。
struct FeedCardView: View {
    let entry: FeedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            // 他人の投稿は本文（種目アイコン＋内容）を1行で見せる。
            if entry.isFromOther {
                Label(entry.title, systemImage: entry.icon)
                    .font(.subheadline).foregroundStyle(Theme.textPrimary)
            }
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
            if entry.isFromOther {
                AvatarView(urlString: entry.authorAvatarURL, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.authorName ?? "ユーザー").font(.subheadline.bold())
                    Text(entry.date, format: .dateTime.month().day().hour().minute())
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: entry.icon)
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
                    .background(iconColor.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title).font(.subheadline.bold())
                    Text(entry.date, format: .dateTime.month().day().hour().minute())
                        .font(.caption2).foregroundStyle(.secondary)
                }
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
