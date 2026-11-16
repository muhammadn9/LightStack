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

    private func oneRepTrack(through end: Double) -> PoseTrack {
        let step = 1 / SyntheticPoseSource.frameRate
        let frames = stride(from: 0.0, through: end, by: step).map { SyntheticPoseSource.frame(at: $0) }
        return PoseTrack(frames: frames, aspectRatio: SyntheticPoseSource.aspect)
    }

    func testSingleRepIsCountedOnlyWhenMinRepsIsOne() {
        let profile = MovementProfileLibrary.profile(for: SyntheticPoseSource.syntheticExerciseName)
        let track = oneRepTrack(through: 4.5)   // still 2 s, then exactly one 2 s rep
        let live = RepDetector.detect(track: track, profile: profile, minReps: 1)
        XCTAssertEqual(live.reps.count, 1)
        XCTAssertGreaterThanOrEqual(live.reps.first?.amplitudeDegrees ?? 0, profile.minAmplitudeDegrees)
        // Final analysis behaviour is unchanged: one rep is still "insufficient".
        let final = RepDetector.detect(track: track, profile: profile)
        XCTAssertEqual(final.reps.count, 0)
        XCTAssertEqual(final.status, .insufficient)
        XCTAssertEqual(FormAnalyzer.analyze(track: track, exerciseName: SyntheticPoseSource.syntheticExerciseName).repCount, 0)
    }

    func testUnfinishedFirstRepIsNotCountedLive() {
        let profile = MovementProfileLibrary.profile(for: SyntheticPoseSource.syntheticExerciseName)
        XCTAssertEqual(RepDetector.detect(track: oneRepTrack(through: 3.2), profile: profile, minReps: 1).reps.count, 0)
        // Standing still is not a rep either.
        XCTAssertEqual(RepDetector.detect(track: oneRepTrack(through: 1.9), profile: profile, minReps: 1).reps.count, 0)
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
