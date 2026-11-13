import XCTest
@testable import Lightstack

final class SyntheticPoseSourceTests: XCTestCase {

    func testFiveRepsOfFramesYieldFiveReps() {
        let profile = MovementProfileLibrary.profile(for: SyntheticPoseSource.syntheticExerciseName)
        XCTAssertEqual(profile.id, "lateralRaise")
        let step = 1 / SyntheticPoseSource.frameRate
        // 2 s standing still, then 5 reps of 2 s each.
        let frames = stride(from: 0.0, through: 12.0, by: step).map { SyntheticPoseSource.frame(at: $0) }
        let track = PoseTrack(frames: frames, aspectRatio: SyntheticPoseSource.aspect)
        XCTAssertEqual(RepDetector.detect(track: track, profile: profile).reps.count, 5)
    }

    func testShoulderAngleSwingsBetweenRestAndTop() {
        XCTAssertEqual(SyntheticPoseSource.shoulderAngle(at: 0), 15, accuracy: 1e-9)
        XCTAssertEqual(SyntheticPoseSource.shoulderAngle(at: 3), 80, accuracy: 1e-9)
        XCTAssertEqual(SyntheticPoseSource.shoulderAngle(at: 4), 15, accuracy: 1e-9)
    }

    func testFrameGeometryMatchesAngle() {
        let frame = SyntheticPoseSource.frame(at: 3)
        let angle = PoseGeometry.angle(in: frame, kind: .shoulder, side: .left, aspect: SyntheticPoseSource.aspect)
        XCTAssertEqual(angle ?? 0, 80, accuracy: 0.5)
    }
}
