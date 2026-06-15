import SwiftUI
import UIKit

/// 共有カードのテーマ（§6.6 テーマ選択）。
enum ShareCardTheme: String, CaseIterable, Identifiable {
    case energy, dark, light
    var id: String { rawValue }

    var label: String {
        switch self {
        case .energy: return "エナジー"
        case .dark: return "ダーク"
        case .light: return "ライト"
        }
    }

    var accent: Color {
        switch self {
        case .energy: return Theme.energy
        case .dark: return Theme.energy
        case .light: return Color(red: 0.2, green: 0.6, blue: 0.1)
        }
    }

    var textColor: Color { self == .light ? .black : .white }
    var overlayOpacity: Double { self == .light ? 0.12 : 0.45 }
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
