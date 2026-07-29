import Foundation

/// 投稿コンポーザのコメントプリセット。
/// 毎回コメントを打つのは負担なので、1 タップで気分を添えられる定型文を用意する。
/// 表示順＝提示順。テキストは本文へ挿入され、そのまま編集できる。
enum PostCaptionPresets {
    struct Preset: Identifiable, Equatable, Sendable {
        /// チップに出す短いラベル。
        let label: String
        /// 本文へ挿入される文字列。
        let text: String
        /// チップの SF Symbol。
        let symbol: String
        var id: String { label }
    }

    static let all: [Preset] = [
        Preset(label: "ベスト更新", text: "ベスト更新！", symbol: "trophy.fill"),
        Preset(label: "追い込めた", text: "しっかり追い込めた。", symbol: "flame.fill"),
        Preset(label: "つらかった", text: "つらかった…！", symbol: "face.dashed"),
        Preset(label: "軽かった", text: "今日は身体が軽い。", symbol: "wind"),
        Preset(label: "調整", text: "今日は軽めに調整。", symbol: "leaf.fill"),
    ]

    /// プリセットを本文に足す。既に含まれていれば二重に足さない（連打で壊れないように）。
    /// 空なら本文そのもの、非空なら改行で継ぐ。
    static func appending(_ preset: Preset, to caption: String) -> String {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(preset.text) else { return caption }
        return trimmed.isEmpty ? preset.text : trimmed + "\n" + preset.text
    }
}
