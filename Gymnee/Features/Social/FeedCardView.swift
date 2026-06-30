import SwiftUI

/// フィード 1 件のカード表示（§6.11 / ⑦）。
/// 記録そのものをコンテンツ化する：自分のワークアウトは主要スタッツ（種目/セット/ボリューム/時間）と
/// 鍛えた部位・PR を自動ハイライト。来店は写真付き。PR 投稿は計測タイプ別トロフィー。
/// 体重/体組成などセンシティブな身体データはフィードには一切露出しない（feed_item の種別に含めない）。
struct FeedCardView: View {
    let entry: FeedEntry

    private var isPRHighlight: Bool { entry.kind == .pr || entry.prCount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            bodyContent

            if let photo = PhotoStore.load(entry.photoFilename) {
                Image(uiImage: photo)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            } else if let ref = entry.photoRef, !ref.isEmpty {
                // 他人の来店写真：ストレージ参照から取得（権限が無ければプレースホルダのまま）。
                SyncedPhoto(filename: nil, ref: ref) { Color.clear }
                    .scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            if let subtitle = entry.subtitle, !subtitle.isEmpty, entry.kind == .visit {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            if !entry.partners.isEmpty {
                Label(entry.partners.joined(separator: "・"), systemImage: "person.2.fill")
                    .font(.caption).foregroundStyle(Theme.energy)
            }
        }
        .gymneeCard(highlighted: isPRHighlight)
    }

    /// 本文。ワークアウトはスタッツがあればリッチに（自分/他人とも）、PRはトロフィー、
    /// それ以外（来店/スタッツ無しの旧投稿）は他人投稿のみ summary を1行表示。
    @ViewBuilder private var bodyContent: some View {
        if entry.kind == .workout, !entry.stats.isEmpty {
            workoutBody
        } else if entry.kind == .pr, entry.prKind != nil {
            prBody
        } else if entry.isFromOther {
            Label(entry.title, systemImage: entry.icon)
                .font(.subheadline).foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - ワークアウト本体（主要スタッツ自動ハイライト）

    @ViewBuilder private var workoutBody: some View {
        if entry.prCount > 0 {
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                Text("PR \(entry.prCount)")
            }
            .font(.caption.bold()).foregroundStyle(Theme.onLime)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.limeFill, in: Capsule())
        }
        if !entry.stats.isEmpty {
            HStack(spacing: 6) {
                ForEach(entry.stats) { statChip($0) }
            }
        }
        if !entry.muscles.isEmpty { muscleRow }
    }

    private func statChip(_ stat: FeedStat) -> some View {
        VStack(spacing: 1) {
            Text(stat.value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(stat.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private var muscleRow: some View {
        HStack(spacing: 5) {
            ForEach(entry.muscles.prefix(8), id: \.self) { mg in
                Circle().fill(Theme.muscleColor(mg)).frame(width: 8, height: 8)
            }
            Text(entry.muscles.prefix(3).map(\.label).joined(separator: "・"))
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - PR 本体（計測タイプ別トロフィー）

    private var prBody: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(Theme.celebration).frame(width: 40, height: 40)
                Image(systemName: entry.prKind?.symbol ?? "trophy.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.onLime)
            }
            VStack(alignment: .leading, spacing: 0) {
                if let kind = entry.prKind { OverlineLabel(text: kind.label) }
                if let v = entry.subtitle, !v.isEmpty {
                    Text(v).font(.numS).foregroundStyle(Theme.lime)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Header

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
                        .lineLimit(2)
                    Text(entry.date, format: .dateTime.month().day().hour().minute())
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            Label(entry.visibility.label, systemImage: visibilityIcon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1).layoutPriority(1)
        }
    }

    private var iconColor: Color {
        switch entry.kind {
        case .visit: return Theme.energy
        case .pr: return Theme.lime
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
