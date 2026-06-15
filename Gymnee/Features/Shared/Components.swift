import SwiftUI

/// 未実装タブの暫定表示（フェーズ進行に伴い各機能画面へ置き換える）。
struct ComingSoonView: View {
    let title: String
    var systemImage: String = "hammer.fill"
    var note: String = "このフェーズは順次実装します。"

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(Theme.energy)
            Text(title).font(.title2.bold())
            Text(note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.groupedBackground)
    }
}

/// セクション見出し。
struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline)
            }
        }
    }
}

/// 数値ステータスのピル表示（連続日数・PR 件数など）。
struct StatPill: View {
    let value: String
    let label: String
    var tint: Color = Theme.energy

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}
