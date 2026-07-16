import SwiftUI
import UIKit

/// 共有カードのテーマ（§6.6 テーマ選択）。
/// transparent は背景を透過にして、ユーザー自身のジム自撮りに重ねられるテンプレ（④）。
enum ShareCardTheme: String, CaseIterable, Identifiable {
    case energy, dark, light, transparent
    var id: String { rawValue }

    var label: String {
        switch self {
        case .energy: return "エナジー"
        case .dark: return "ダーク"
        case .light: return "ライト"
        case .transparent: return "透過"
        }
    }

    var accent: Color {
        switch self {
        case .energy: return Theme.energy
        case .dark: return Theme.energy
        case .light: return Color(red: 0.2, green: 0.6, blue: 0.1)
        case .transparent: return Theme.energy
        }
    }

    var textColor: Color { self == .light ? .black : .white }
    var overlayOpacity: Double {
        switch self {
        case .light: return 0.12
        case .transparent: return 0   // 透過：自撮りの上に重ねるので暗幕を敷かない
        default: return 0.45
        }
    }
    /// 透過テンプレ：背景画像/暗幕を使わず、文字に影を付けて任意の写真の上で読めるようにする。
    var isTransparent: Bool { self == .transparent }
}

/// メニュー一覧の1行（種目名＋ベストセット表記＋セット数。PR 種目はトロフィー付き）。
struct ShareCardExerciseLine: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let isPR: Bool
}

/// 下部スタット行の1項目（値＋ラベル。例: "7,470kg" / "総量"）。
struct ShareCardStat: Identifiable {
    var id: String { label }
    let value: String
    let label: String
}

/// 共有カードに載せる内容（§6.6 種目/連続日数/PR/ジム名）。表示項目はトグルで選択可能。
struct ShareCardContent {
    var image: UIImage?
    var date: Date = .now
    var gymName: String?
    var streak: Int?
    var prText: String?
    var exerciseSummary: String?
    /// カード中央のメニュー一覧（空なら従来どおりサマリ1行のみの表示）。
    var exerciseLines: [ShareCardExerciseLine] = []
    /// 下部のスタット行（総量・セット数・時間）。空なら exerciseSummary を表示する。
    var stats: [ShareCardStat] = []

    var showGym = true
    var showStreak = true
    var showPR = true
    var showExercises = true
}
