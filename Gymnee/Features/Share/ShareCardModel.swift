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

/// 共有カードに載せる内容（§6.6 種目/連続日数/PR/ジム名）。表示項目はトグルで選択可能。
struct ShareCardContent {
    var image: UIImage?
    var date: Date = .now
    var gymName: String?
    var streak: Int?
    var prText: String?
    var exerciseSummary: String?

    var showGym = true
    var showStreak = true
    var showPR = true
    var showExercises = true
}
