import SwiftUI
import SafariServices

// MARK: - 価格表示

/// 参考価格表示ヘルパ（円）。アフィリエイト方式では提携先の価格が正のため「目安」として扱う。
func formatPrice(_ value: Decimal) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "JPY"
    f.maximumFractionDigits = 0
    f.locale = Locale(identifier: "ja_JP")
    return f.string(from: value as NSDecimalNumber) ?? "¥\(value)"
}

/// 「目安 ¥3,980〜」形式。提携先で価格が変動するため幅を持たせて表示する。
func formatReferencePrice(_ value: Decimal) -> String {
    "目安 \(formatPrice(value))〜"
}

// MARK: - ステマ規制（景表法）開示

/// アフィリエイト関係の明示（2023/10 施行のステルスマーケティング規制対応）。
/// 商品一覧・詳細など、外部送客リンクが現れる箇所に必ず表示する。
struct AffiliateDisclosure: View {
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("広告")
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.18), in: Capsule())
            if !compact {
                Text("Gymnee は提携先サイトへのリンクを掲載し、購入に応じて手数料を得ることがあります。価格・在庫・購入手続きは各提携先サイトに従います。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - アプリ内ブラウザ（SFSafariViewController）

/// アフィリエイトリンクをアプリ内ブラウザで開く（計測クッキー保持・離脱しにくくUX良好）。
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// `.sheet(item:)` 用に URL を Identifiable 化する薄いラッパ。
struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
