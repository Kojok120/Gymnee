import XCTest
import SwiftUI
@testable import Gymnee

/// 人体図のパス資産のテスト。
/// 図形は MuscleMap（MIT）から取り込んだ解剖パスなので、**形そのもの**ではなく
/// 「Gymnee 側の配り方」＝座標変換・部位マッピング・タップ判定を検証する。
final class BodyMapPathsTests: XCTestCase {

    /// 実際の描画に近いサイズ（元データの縦横比に合わせる）。
    private var rect: CGRect {
        let h: CGFloat = 400
        return CGRect(x: 0, y: 0, width: h * BodyMapPaths.aspectRatio, height: h)
    }

    private func hit(_ face: BodyMapPaths.Face, _ nx: CGFloat, _ ny: CGFloat) -> MuscleGroup? {
        let r = rect
        return BodyMapPaths.muscle(at: CGPoint(x: r.minX + nx * r.width, y: r.minY + ny * r.height),
                                   face: face, in: r)
    }

    // MARK: - 資産の健全性

    func testEveryTrackedMuscleIsDrawnSomewhere() {
        // 疲労度を出す8部位すべてに、正面か背面のどこかで塗る場所があること。
        // これが崩れると「鍛えたのに人体図が光らない」部位が出る。
        let drawn = Set((BodyMapArtwork.front + BodyMapArtwork.back).compactMap(\.muscle))
        for muscle in RecoveryAnalyzer.trackedMuscles {
            XCTAssertTrue(drawn.contains(muscle), "\(muscle.rawValue) が人体図に描かれていない")
        }
    }

    func testRegionIdsAreUniquePerFace() {
        for face in BodyMapPaths.Face.allCases {
            let ids = BodyMapPaths.regions(for: face, in: rect).map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(face.rawValue) に重複 id がある（ForEach がアサーション落ちする）")
        }
    }

    func testEveryRegionHasAtLeastOneNonEmptyPath() {
        // パース失敗（コマンド未対応・データ破損）を検知する。
        for face in BodyMapPaths.Face.allCases {
            for region in BodyMapPaths.regions(for: face, in: rect) {
                XCTAssertFalse(region.paths.isEmpty, "\(region.id) にパスが無い")
                XCTAssertTrue(region.paths.allSatisfy { !$0.isEmpty }, "\(region.id) に空のパスがある")
            }
        }
    }

    func testRegionsStayInsideBounds() {
        // はみ出すと隣のカードに描画が漏れる。丸め誤差ぶんだけ許容する。
        let r = rect
        let bounds = r.insetBy(dx: -1.5, dy: -1.5)
        for face in BodyMapPaths.Face.allCases {
            for region in BodyMapPaths.regions(for: face, in: r) {
                for path in region.paths {
                    XCTAssertTrue(bounds.contains(path.boundingRect),
                                  "\(region.id) が枠外にはみ出している: \(path.boundingRect)")
                }
            }
        }
    }

    func testArtworkFillsMostOfTheFrame() {
        // 座標変換の取り違え（オフセット・スケール）を検知する。
        // 人体は枠の高さのほとんどを使い、幅も半分以上を占めるはず。
        let r = rect
        for face in BodyMapPaths.Face.allCases {
            let boxes = BodyMapPaths.regions(for: face, in: r).flatMap { $0.paths.map(\.boundingRect) }
            let union = boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
            XCTAssertGreaterThan(union.height, r.height * 0.9, "\(face.rawValue) の人体が縦に小さすぎる")
            XCTAssertGreaterThan(union.width, r.width * 0.5, "\(face.rawValue) の人体が横に小さすぎる")
            // 左右に極端に寄っていない（中央に配置されている）。
            XCTAssertEqual(union.midX, r.midX, accuracy: r.width * 0.06, "\(face.rawValue) の人体が中央から外れている")
        }
    }

    func testScalingIsProportional() {
        // 枠を変えても縦横比が保たれる（人体が歪まない）。
        let small = CGRect(x: 0, y: 0, width: 100 * BodyMapPaths.aspectRatio, height: 100)
        let large = CGRect(x: 0, y: 0, width: 400 * BodyMapPaths.aspectRatio, height: 400)
        func unionBox(_ r: CGRect) -> CGRect {
            let boxes = BodyMapPaths.regions(for: .front, in: r).flatMap { $0.paths.map(\.boundingRect) }
            return boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
        }
        let a = unionBox(small), b = unionBox(large)
        XCTAssertEqual(a.width / a.height, b.width / b.height, accuracy: 0.02)
    }

    // MARK: - 部位マッピング

    func testDecorationsAreNotTappable() {
        // 頭・首・手足は装飾扱い（muscle=nil）で選択対象にしない。
        let decorations = ["head", "hair", "neck", "hands", "feet", "ankles", "knees"]
        for region in BodyMapArtwork.front + BodyMapArtwork.back where decorations.contains(region.id) {
            XCTAssertNil(region.muscle, "\(region.id) は装飾のはずが部位に割り当てられている")
        }
    }

    func testOverlappingSubGroupsAreExcluded() {
        // 親と重なるサブグループを取り込むと二重描画＆タップの取り合いになる。
        let excluded = ["upperChest", "lowerChest", "upperAbs", "lowerAbs",
                        "innerQuad", "outerQuad", "frontDeltoid", "hipFlexors"]
        let ids = Set((BodyMapArtwork.front + BodyMapArtwork.back).map(\.id))
        for id in excluded {
            XCTAssertFalse(ids.contains(id), "\(id) は取り込まない約束（親と重なる）")
        }
    }

    func testFrontAndBackMapToExpectedMuscles() {
        func muscle(_ regions: [BodyMapArtwork.Region], _ id: String) -> MuscleGroup? {
            regions.first { $0.id == id }?.muscle
        }
        XCTAssertEqual(muscle(BodyMapArtwork.front, "chest"), .chest)
        XCTAssertEqual(muscle(BodyMapArtwork.front, "abs"), .abs)
        XCTAssertEqual(muscle(BodyMapArtwork.front, "obliques"), .core)
        XCTAssertEqual(muscle(BodyMapArtwork.front, "deltoids"), .shoulders)
        XCTAssertEqual(muscle(BodyMapArtwork.front, "biceps"), .arms)
        XCTAssertEqual(muscle(BodyMapArtwork.front, "quadriceps"), .legs)
        XCTAssertEqual(muscle(BodyMapArtwork.back, "gluteal"), .glutes)
        XCTAssertEqual(muscle(BodyMapArtwork.back, "hamstring"), .legs)
        XCTAssertEqual(muscle(BodyMapArtwork.back, "upperBack"), .back)
        XCTAssertEqual(muscle(BodyMapArtwork.back, "lowerBack"), .core)
    }

    // MARK: - タップ判定

    func testTapOnBodyResolvesToSomeMuscle() {
        // 体の上を格子状に走査して、十分な数の点が部位に当たること
        // （座標変換が壊れると全部 nil になる）。
        // 正中線（胸骨・背骨）は左右の筋の“隙間”なので、中心線だけを見ると当たらない点に注意。
        for face in BodyMapPaths.Face.allCases {
            var hits = 0, total = 0
            for nx in stride(from: 0.34, through: 0.66, by: 0.04) {
                for ny in stride(from: 0.28, through: 0.80, by: 0.04) {
                    total += 1
                    if hit(face, nx, ny) != nil { hits += 1 }
                }
            }
            // 走査窓には正中線・脚の間・体の輪郭外の余白が含まれるため 100% にはならない。
            // 座標変換が壊れると 0 になるので、そこを検知できれば十分。
            XCTAssertGreaterThan(Double(hits) / Double(total), 0.3,
                                 "\(face.rawValue) で体のタップがほとんど当たらない（\(hits)/\(total)）")
        }
    }

    func testMajorMusclesAreReachableByTap() {
        // 主要部位が「どこかしらのタップで必ず選べる」こと。
        // 描かれていても全部が別の領域に覆われていると選べない、という状態を防ぐ。
        var reachable = Set<MuscleGroup>()
        for face in BodyMapPaths.Face.allCases {
            for nx in stride(from: 0.20, through: 0.80, by: 0.02) {
                for ny in stride(from: 0.10, through: 0.95, by: 0.02) {
                    if let m = hit(face, nx, ny) { reachable.insert(m) }
                }
            }
        }
        for muscle in RecoveryAnalyzer.trackedMuscles {
            XCTAssertTrue(reachable.contains(muscle), "\(muscle.rawValue) がタップで選べない")
        }
    }

    func testTapOutsideBodyHitsNothing() {
        // 四隅の余白をタップしても部位が選ばれない（誤爆でシートが開かない）。
        for face in BodyMapPaths.Face.allCases {
            XCTAssertNil(hit(face, 0.02, 0.02))
            XCTAssertNil(hit(face, 0.98, 0.02))
            XCTAssertNil(hit(face, 0.02, 0.98))
            XCTAssertNil(hit(face, 0.98, 0.98))
        }
    }

    func testTapIsStableAcrossFrameSizes() {
        // 枠サイズが変わっても、同じ相対位置は同じ部位に解決される。
        func hitIn(_ h: CGFloat, _ nx: CGFloat, _ ny: CGFloat) -> MuscleGroup? {
            let r = CGRect(x: 0, y: 0, width: h * BodyMapPaths.aspectRatio, height: h)
            return BodyMapPaths.muscle(at: CGPoint(x: r.minX + nx * r.width, y: r.minY + ny * r.height),
                                       face: .front, in: r)
        }
        for (nx, ny) in [(0.5, 0.33), (0.5, 0.42), (0.5, 0.60)] {
            XCTAssertEqual(hitIn(240, nx, ny), hitIn(600, nx, ny), "(\(nx),\(ny)) がサイズで変わる")
        }
    }
}
