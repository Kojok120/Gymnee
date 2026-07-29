import XCTest
import SwiftUI
@testable import Gymnee

/// 人体図のパス資産のテスト。
/// タップ判定は `Path.contains(_:)` に依存するので、**部位が重なって誤爆しないこと**が要件。
final class BodyMapPathsTests: XCTestCase {

    /// 実際の描画に近いサイズ（縦長 0.52 のアスペクト比）。
    private let rect = CGRect(x: 0, y: 0, width: 208, height: 400)

    private func hitMuscle(_ face: BodyMapPaths.Face, at normalized: CGPoint) -> MuscleGroup? {
        let point = CGPoint(x: rect.minX + normalized.x * rect.width, y: rect.minY + normalized.y * rect.height)
        for region in BodyMapPaths.regions(for: face).reversed() {
            guard let muscle = region.muscle else { continue }
            if region.path(rect).contains(point) { return muscle }
        }
        return nil
    }

    // MARK: - 資産の健全性

    func testEveryTrackedMuscleIsDrawnSomewhere() {
        // 疲労度を出す8部位すべてに、正面か背面のどこかで塗る場所があること。
        // これが崩れると「鍛えたのに人体図が光らない」部位が出る。
        let drawn = Set(
            (BodyMapPaths.front + BodyMapPaths.back).compactMap(\.muscle)
        )
        for muscle in RecoveryAnalyzer.trackedMuscles {
            XCTAssertTrue(drawn.contains(muscle), "\(muscle.rawValue) が人体図に描かれていない")
        }
    }

    func testRegionIdsAreUniquePerFace() {
        for face in BodyMapPaths.Face.allCases {
            let ids = BodyMapPaths.regions(for: face).map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(face.rawValue) に重複 id がある（ForEach がアサーション落ちする）")
        }
    }

    func testAllRegionsProduceNonEmptyPaths() {
        for face in BodyMapPaths.Face.allCases {
            for region in BodyMapPaths.regions(for: face) {
                XCTAssertFalse(region.path(rect).isEmpty, "\(region.id) のパスが空")
            }
        }
    }

    func testRegionsStayInsideBounds() {
        // はみ出すと隣のカードに描画が漏れる。少しの余白を許容して検査する。
        let tolerance: CGFloat = 1
        let bounds = rect.insetBy(dx: -tolerance, dy: -tolerance)
        for face in BodyMapPaths.Face.allCases {
            for region in BodyMapPaths.regions(for: face) {
                let b = region.path(rect).boundingRect
                XCTAssertTrue(bounds.contains(b), "\(region.id) が枠外にはみ出している: \(b)")
            }
        }
    }

    func testLeftAndRightAreSymmetric() {
        // 左右ペアは x 反転で同じ形（面積が一致する）。
        for face in BodyMapPaths.Face.allCases {
            let byId = Dictionary(uniqueKeysWithValues: BodyMapPaths.regions(for: face).map { ($0.id, $0) })
            for region in BodyMapPaths.regions(for: face) where region.id.hasSuffix(".l") {
                let mirrorId = region.id.replacingOccurrences(of: ".l", with: ".r")
                guard let mirror = byId[mirrorId] else {
                    XCTFail("\(region.id) に対応する \(mirrorId) が無い"); continue
                }
                let a = region.path(rect).boundingRect
                let b = mirror.path(rect).boundingRect
                XCTAssertEqual(a.width, b.width, accuracy: 0.5)
                XCTAssertEqual(a.height, b.height, accuracy: 0.5)
                // 中心が rect の中央に対して線対称。
                XCTAssertEqual(a.midX + b.midX, rect.width, accuracy: 1.0)
                XCTAssertEqual(a.midY, b.midY, accuracy: 0.5)
            }
        }
    }

    // MARK: - タップ判定

    func testFrontHitsExpectedMuscles() {
        // 各ブロックの内部に確実に入る点でヒットすること。
        XCTAssertEqual(hitMuscle(.front, at: CGPoint(x: 0.45, y: 0.245)), .chest)
        XCTAssertEqual(hitMuscle(.front, at: CGPoint(x: 0.455, y: 0.36)), .abs)
        XCTAssertEqual(hitMuscle(.front, at: CGPoint(x: 0.345, y: 0.235)), .shoulders)
        XCTAssertEqual(hitMuscle(.front, at: CGPoint(x: 0.318, y: 0.330)), .arms)
        XCTAssertEqual(hitMuscle(.front, at: CGPoint(x: 0.45, y: 0.56)), .legs)
    }

    func testBackHitsExpectedMuscles() {
        XCTAssertEqual(hitMuscle(.back, at: CGPoint(x: 0.455, y: 0.22)), .back)
        XCTAssertEqual(hitMuscle(.back, at: CGPoint(x: 0.455, y: 0.32)), .back)
        XCTAssertEqual(hitMuscle(.back, at: CGPoint(x: 0.45, y: 0.50)), .glutes)
        XCTAssertEqual(hitMuscle(.back, at: CGPoint(x: 0.45, y: 0.61)), .legs)
        XCTAssertEqual(hitMuscle(.back, at: CGPoint(x: 0.318, y: 0.330)), .arms)
    }

    func testTapOutsideBodyHitsNothing() {
        // 余白をタップしても部位が選ばれない（誤爆でシートが開かない）。
        XCTAssertNil(hitMuscle(.front, at: CGPoint(x: 0.03, y: 0.03)))
        XCTAssertNil(hitMuscle(.front, at: CGPoint(x: 0.97, y: 0.97)))
        XCTAssertNil(hitMuscle(.back, at: CGPoint(x: 0.5, y: 0.98)))
    }

    func testHeadAndNeckAreNotTappable() {
        // 装飾（muscle=nil）は選択対象にしない。
        XCTAssertNil(hitMuscle(.front, at: CGPoint(x: 0.5, y: 0.078)))
        XCTAssertNil(hitMuscle(.front, at: CGPoint(x: 0.5, y: 0.163)))
    }

    func testMirroredTapsResolveToSameMuscle() {
        // 左右どちらを押しても同じ部位が返る。
        for y in [0.245, 0.33, 0.56] {
            let left = hitMuscle(.front, at: CGPoint(x: 0.45, y: y))
            let right = hitMuscle(.front, at: CGPoint(x: 0.55, y: y))
            XCTAssertEqual(left, right, "y=\(y) で左右の判定が食い違う")
        }
    }
}
