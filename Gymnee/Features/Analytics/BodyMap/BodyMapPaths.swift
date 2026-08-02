import SwiftUI

/// 人体図の筋群パス。
///
/// 図形は MuscleMap（MIT・[[NOTICE.md]]）の解剖パスを `BodyMapArtwork` に取り込んだもので、
/// ここはそれを **Gymnee の描画都合に合わせて配る層**（座標変換・部位まとめ・タップ判定）。
/// 手描きの簡易ブロックから差し替えた経緯があるため、責務を分けてある:
/// - `BodyMapArtwork` … 図形そのもの（自動生成・手で編集しない）
/// - `BodyMapPaths`   … 実サイズへの写像と、`MuscleGroup` 単位のまとめ
///
/// 塗りの単位は既存の `MuscleGroup`（8部位）。元データは 20 以上の筋に分かれているが、
/// 色は所属する MuscleGroup で決まる。将来 MuscleGroup を細分化してもこの資産は使い回せる。
enum BodyMapPaths {

    /// 表示する面。
    enum Face: String, CaseIterable, Identifiable, Sendable {
        case front, back
        var id: String { rawValue }
        var label: String { self == .front ? "正面" : "背面" }
    }

    /// 描画・判定の単位。1 領域が複数の閉じた図形を持つことがある（左右のペアなど）。
    struct Region: Identifiable {
        let id: String
        /// 塗り色を決める部位。nil＝装飾（頭・首・手足。塗らずタップもしない）。
        let muscle: MuscleGroup?
        /// 実サイズへ写した Path 群。
        let paths: [Path]
    }

    /// 元データの縦横比（描画枠のアスペクト比に使う）。
    static var aspectRatio: CGFloat { BodyMapArtwork.viewBox.width / BodyMapArtwork.viewBox.height }

    /// 指定サイズの矩形に収めた領域一覧。
    /// viewBox 座標をアスペクト比を保ったまま `rect` の中央へ写す（縦横比が崩れると人体が歪む）。
    static func regions(for face: Face, in rect: CGRect) -> [Region] {
        let box = BodyMapArtwork.viewBox
        let scale = min(rect.width / box.width, rect.height / box.height)
        // 背面は元シートの右側に置かれているため x が backOffsetX だけずれている。
        let originX = box.minX + (face == .back ? BodyMapArtwork.backOffsetX : 0)
        let offsetX = rect.midX - (originX + box.width / 2) * scale
        let offsetY = rect.midY - (box.minY + box.height / 2) * scale

        let source = face == .front ? BodyMapArtwork.front : BodyMapArtwork.back
        return source.map { region in
            Region(
                id: region.id,
                muscle: region.muscle,
                paths: region.commands.map {
                    PathBuilder.buildPath(from: $0, scale: scale, offsetX: offsetX, offsetY: offsetY)
                }
            )
        }
    }

    /// タップ位置に載っている部位。手前に描いたものを優先して逆順に判定する。
    ///
    /// 実行時の当たり判定は `BodyMapView` が部位ごとの `contentShape` で行う（押し込み・
    /// ハプティクスのために部位を Button にしたため）。同じパス・同じ「手前優先」なので、
    /// ここは資産のマッピングを検証するための参照実装として残している。
    static func muscle(at point: CGPoint, face: Face, in rect: CGRect) -> MuscleGroup? {
        for region in regions(for: face, in: rect).reversed() {
            guard let muscle = region.muscle else { continue }
            if region.paths.contains(where: { $0.contains(point) }) { return muscle }
        }
        return nil
    }
}
