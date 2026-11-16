import XCTest
@testable import Lightstack

final class SkeletonOverlayMappingTests: XCTestCase {

    private func map(_ x: Double, _ y: Double, aspect: Double, size: CGSize) -> CGPoint {
        SkeletonOverlayView.point(for: PosePoint(x: x, y: y, confidence: 1), aspectRatio: aspect, in: size)
    }

    func testViewWiderThanImageCropsTopAndBottom() {
        // Image 0.5 wide x 1 tall into 200x100: scaled to 200x400, 150 cropped off top and bottom.
        let size = CGSize(width: 200, height: 100)
        let centre = map(0.5, 0.5, aspect: 0.5, size: size)
        XCTAssertEqual(centre.x, 100, accuracy: 1e-6)
        XCTAssertEqual(centre.y, 50, accuracy: 1e-6)
        let topLeft = map(0, 0, aspect: 0.5, size: size)
        XCTAssertEqual(topLeft.x, 0, accuracy: 1e-6)
        XCTAssertEqual(topLeft.y, -150, accuracy: 1e-6)
    }

    func testViewTallerThanImageCropsLeftAndRight() {
        // Square image into 100x400: scaled to 400x400, 150 cropped off each side.
        let size = CGSize(width: 100, height: 400)
        let topLeft = map(0, 0, aspect: 1, size: size)
        XCTAssertEqual(topLeft.x, -150, accuracy: 1e-6)
        XCTAssertEqual(topLeft.y, 0, accuracy: 1e-6)
        let centre = map(0.5, 0.5, aspect: 1, size: size)
        XCTAssertEqual(centre.x, 50, accuracy: 1e-6)
        XCTAssertEqual(centre.y, 200, accuracy: 1e-6)
    }

    func testSameAspectMapsStraightThrough() {
        let size = CGSize(width: 90, height: 160)
        let p = map(0.25, 0.75, aspect: 90.0 / 160.0, size: size)
        XCTAssertEqual(p.x, 22.5, accuracy: 1e-6)
        XCTAssertEqual(p.y, 120, accuracy: 1e-6)
    }
}
