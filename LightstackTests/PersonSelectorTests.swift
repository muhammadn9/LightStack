import XCTest
@testable import Lightstack

final class PersonSelectorTests: XCTestCase {

    /// Four confident joints spread over a box centred on (cx, cy) with the given half size.
    private func person(cx: Double, cy: Double, half: Double, confidence: Double = 0.9) -> [BodyJoint: PosePoint] {
        [
            .leftShoulder: PosePoint(x: cx - half, y: cy - half, confidence: confidence),
            .rightShoulder: PosePoint(x: cx + half, y: cy - half, confidence: confidence),
            .leftHip: PosePoint(x: cx - half, y: cy + half, confidence: confidence),
            .rightHip: PosePoint(x: cx + half, y: cy + half, confidence: confidence)
        ]
    }

    func testFirstFramePicksLargest() {
        let small = person(cx: 0.2, cy: 0.5, half: 0.05)
        let big = person(cx: 0.7, cy: 0.5, half: 0.2)
        XCTAssertEqual(PersonSelector.select(candidates: [small, big], previousCenter: nil)?.index, 1)
    }

    func testBystanderWalkingPastDoesNotStealTracking() {
        let me = person(cx: 0.3, cy: 0.5, half: 0.18)
        // A bystander passes nearer the camera: a bit bigger than me, but far from where I was.
        let bystander = person(cx: 0.8, cy: 0.5, half: 0.2)
        let previous = PersonSelector.Center(x: 0.3, y: 0.5)
        XCTAssertEqual(PersonSelector.select(candidates: [bystander, me], previousCenter: previous)?.index, 1)
    }

    func testMuchLargerPersonTakesOverWhenTrackedPersonIsTiny() {
        let tiny = person(cx: 0.3, cy: 0.5, half: 0.05)
        let big = person(cx: 0.8, cy: 0.5, half: 0.25)
        let previous = PersonSelector.Center(x: 0.3, y: 0.5)
        XCTAssertEqual(PersonSelector.select(candidates: [tiny, big], previousCenter: previous)?.index, 1)
    }

    func testIgnoresCandidatesWithTooFewConfidentJoints() {
        let faint = person(cx: 0.5, cy: 0.5, half: 0.3, confidence: 0.1)
        var sparse = person(cx: 0.5, cy: 0.5, half: 0.3)
        sparse.removeValue(forKey: .leftHip)
        sparse.removeValue(forKey: .rightHip)
        XCTAssertNil(PersonSelector.select(candidates: [faint, sparse], previousCenter: nil))
        XCTAssertNil(PersonSelector.select(candidates: [], previousCenter: nil))
    }

    func testReturnsIndexIntoOriginalArrayAndCenter() {
        let faint = person(cx: 0.5, cy: 0.5, half: 0.3, confidence: 0.1)
        let ok = person(cx: 0.4, cy: 0.6, half: 0.1)
        let selection = PersonSelector.select(candidates: [faint, ok], previousCenter: nil)
        XCTAssertEqual(selection?.index, 1)
        XCTAssertEqual(selection?.center.x ?? 0, 0.4, accuracy: 1e-9)
        XCTAssertEqual(selection?.center.y ?? 0, 0.6, accuracy: 1e-9)
    }
}
