import SwiftUI

/// アイコンに使えるプリセット（画像アセットを増やさず、SF Symbol × ブランドカラーで作る）。
///
/// 写真を用意するのが面倒な人でも 1 タップで「自分のアイコン」を決められるようにするための仕組み。
/// 保存先は `Profile.avatarURL` で、`preset://<symbol>/<colorIndex>` という擬似 URL 形式にしている。
/// これにより**サーバーのスキーマ変更なしで他ユーザーにも同期される**（avatar_url は既存の text 列）。
enum AvatarPreset {
    /// 選べるシンボル（表示順）。
    static let symbols = [
        "dumbbell.fill", "figure.strengthtraining.traditional", "flame.fill",
        "bolt.fill", "trophy.fill", "heart.fill", "leaf.fill", "mountain.2.fill",
    ]

    /// 選べる背景色。Theme のセマンティックトークンから採る。
    /// **lime（= energy / success / accent）は「達成・アクティブ状態」の予約色なので入れない**
    /// （AGENTS.md のデザイン規約。アイコンで乱用すると達成表現の意味が薄れる）。
    static let colors: [Color] = [
        Theme.info, Theme.warning, Theme.danger, Theme.series2, Theme.deep, Theme.textSecondary,
    ]

    static let scheme = "preset://"

    /// `preset://<symbol>/<colorIndex>` を組み立てる。
    static func urlString(symbol: String, colorIndex: Int) -> String {
        "\(scheme)\(symbol)/\(colorIndex)"
    }

    /// 保存文字列を (symbol, color) に戻す。プリセットでなければ nil。
    /// 未知のシンボル・範囲外の色は既定へ丸めて、壊れた値でも必ず描けるようにする。
    static func parse(_ urlString: String?) -> (symbol: String, color: Color)? {
        guard let urlString, urlString.hasPrefix(scheme) else { return nil }
        let body = String(urlString.dropFirst(scheme.count))
        let parts = body.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let rawSymbol = parts.first.map(String.init), !rawSymbol.isEmpty else { return nil }
        let symbol = symbols.contains(rawSymbol) ? rawSymbol : symbols[0]
        let index = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        let color = colors.indices.contains(index) ? colors[index] : colors[0]
        return (symbol, color)
    }

    /// プリセット文字列かどうか（写真アイコンと区別するため）。
    static func isPreset(_ urlString: String?) -> Bool { parse(urlString) != nil }
}

/// アバター画像を丸く表示。
/// 端末ローカルのキャッシュ（自分用＝即時）→ プリセット → サーバー公開URL → 既定シンボル の順に解決する。
/// 自分の画像は PhotoStore に保存しファイル名を `@AppStorage("gymnee.avatarFilename")`、
/// 公開URL（またはプリセット文字列）を `@AppStorage("gymnee.avatarURL")` に持つ。他人は urlString のみ。
struct AvatarView: View {
    var filename: String = ""
    var urlString: String? = nil
    var size: CGFloat = 60

    var body: some View {
        Group {
            if let preset = AvatarPreset.parse(urlString) {
                // プリセットは写真より優先（プリセットへ切り替えた後も古いローカル写真を出さない）。
                presetIcon(symbol: preset.symbol, color: preset.color)
            } else if !filename.isEmpty, let image = PhotoStore.load(filename) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        symbol
                    }
                }
            } else {
                symbol
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func presetIcon(symbol: String, color: Color) -> some View {
        ZStack {
            color
            Image(systemName: symbol)
                .resizable().scaledToFit()
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(size * 0.24)
        }
    }

    private var symbol: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable().scaledToFit()
            .foregroundStyle(Theme.lime)
    }
}

/// アイコンの選択 UI（初期設定・プロフィール編集で共用）。
/// プリセットの横並びと「写真を選ぶ」を 1 箇所にまとめ、どちらを選んでも同じ場所に反映される。
struct AvatarPickerRow: View {
    /// 選択中のプリセット文字列（写真を選んでいる間は nil）。
    @Binding var presetURLString: String?
    /// 「写真を選ぶ」が押されたとき。
    var onPickPhoto: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(Array(AvatarPreset.symbols.enumerated()), id: \.offset) { i, symbol in
                        let value = AvatarPreset.urlString(symbol: symbol, colorIndex: i % AvatarPreset.colors.count)
                        Button {
                            presetURLString = value
                        } label: {
                            AvatarView(urlString: value, size: 56)
                                .overlay {
                                    Circle().strokeBorder(
                                        presetURLString == value ? Theme.lime : .clear,
                                        lineWidth: 3
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("アイコン候補 \(i + 1)")
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 3)
            }
            Button(action: onPickPhoto) {
                Label("写真から選ぶ", systemImage: "photo.on.rectangle")
                    .font(.subheadline)
            }
        }
    }
}
