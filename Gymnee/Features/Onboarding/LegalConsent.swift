import SwiftUI
import UIKit

/// 規約・プライバシーポリシーの公式URL（gymnee.app）。設定画面とサインイン導線で共用する単一の出所。
enum LegalLinks {
    static let terms = URL(string: "https://gymnee.app/terms-of-service.html")!
    static let privacy = URL(string: "https://gymnee.app/privacy-policy.html")!
}

/// サインイン導線に添える規約同意フッター。
/// App Store ガイドライン1.2（UGC）は「登録・ログインの前に EULA / 利用規約を提示する」ことを求めるため、
/// 各サインイン導線（OnboardingView / BackendSignInButtons）にこのフッターを置く。
/// 利用規約・プライバシーポリシーはタップで開き、離脱せずアプリ内 SafariView に表示する。
struct LegalAgreementFooter: View {
    /// 表示先の背景に応じた配色。onDark は常時ダーク背景（Onboarding のヒーロー）、
    /// adaptive はシステム背景（サインイン促しシート）でライト/ダークに追従する。
    enum Appearance {
        case onDark
        case adaptive
    }

    var appearance: Appearance = .adaptive

    @State private var browserURL: IdentifiableURL?

    var body: some View {
        Text(agreementText)
            .font(.caption2)
            .foregroundStyle(bodyColor)
            .multilineTextAlignment(.center)
            // リンクタップを横取りし、システムブラウザへ離脱せずアプリ内 SafariView で開く。
            .environment(\.openURL, OpenURLAction { url in
                browserURL = IdentifiableURL(url: url)
                return .handled
            })
            .sheet(item: $browserURL) { item in
                SafariView(url: item.url).ignoresSafeArea()
            }
    }

    private var bodyColor: Color {
        switch appearance {
        case .onDark: return Theme.textOnDarkSecondary
        case .adaptive: return Theme.textSecondary
        }
    }

    private var agreementText: AttributedString {
        var result = AttributedString("続けると")
        result += link("利用規約", url: LegalLinks.terms)
        result += AttributedString("と")
        result += link("プライバシーポリシー", url: LegalLinks.privacy)
        result += AttributedString("に同意したものとみなされます。")
        return result
    }

    private func link(_ label: String, url: URL) -> AttributedString {
        var segment = AttributedString(label)
        segment.link = url
        // lime は達成・アクティブ状態専用のため、リンクには info(青) を使う。
        segment.foregroundColor = Theme.info
        segment.underlineStyle = .single
        return segment
    }
}
