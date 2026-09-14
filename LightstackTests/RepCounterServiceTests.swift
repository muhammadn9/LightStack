import XCTest
import Vision
@testable import Lightstack

/// Tests for RepCounterService squat rep detection using synthetic pose sequences.
///
/// Squat config (from RepCounterService): hip-knee-ankle angle,
/// startAngle = 155, endAngle = 90, shallowThreshold = 120.
/// Detection threshold = (155 + 90) / 2 = 122.5.
final class RepCounterServiceTests: XCTestCase {

    private let service = RepCounterService()
    private let frameInterval: TimeInterval = 1.0 / 30.0

    // MARK: - Pose construction helpers

    /// Builds a BodyPose where the hip-knee-ankle angle on both sides equals `kneeAngle` degrees.
    ///
    /// Knee is placed at the origin, ankle directly below the knee (0, -1), and the hip is
    /// positioned at (sin(angle), -cos(angle)) so that `angle(from: hip, through: knee, to: ankle)`
    /// evaluates to exactly `kneeAngle` (per BodyPose.angle's atan2/abs formula).
    /// Both left and right sides are populated identically since the squat config bilaterally
    /// averages left and right knee angles.
    private func makePose(kneeAngleDegrees: Double, timestamp: TimeInterval) -> BodyPose {
        let theta = kneeAngleDegrees * .pi / 180.0
        let knee = CGPoint(x: 0, y: 0)
        let ankle = CGPoint(x: 0, y: -1)
        let hip = CGPoint(x: sin(theta), y: -cos(theta))

        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        var confidences: [VNHumanBodyPoseObservation.JointName: Float] = [:]

        for jointName: VNHumanBodyPoseObservation.JointName in [
            .leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle,
            .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
            .leftWrist, .rightWrist, .neck
        ] {
            confidences[jointName] = 1.0
        }

        joints[.leftHip] = hip
        joints[.leftKnee] = knee
        joints[.leftAnkle] = ankle
        joints[.rightHip] = hip
        joints[.rightKnee] = knee
        joints[.rightAnkle] = ankle

        // Provide stable positions for joints used by the symmetry score and the
        // IIR smoothing filter so they don't introduce NaNs.
        joints[.leftShoulder] = CGPoint(x: -1, y: 1)
        joints[.rightShoulder] = CGPoint(x: 1, y: 1)
        joints[.leftElbow] = CGPoint(x: -1, y: 0.5)
        joints[.rightElbow] = CGPoint(x: 1, y: 0.5)
        joints[.leftWrist] = CGPoint(x: -1, y: 0)
        joints[.rightWrist] = CGPoint(x: 1, y: 0)
        joints[.neck] = CGPoint(x: 0, y: 1)

        return BodyPose(timestamp: timestamp, joints: joints, confidences: confidences)
    }

    /// Builds a sequence of poses tracing a triangle wave between `topAngle` and `bottomAngle`,
    /// repeated `repCount` times, each rep taking `framesPerRep` frames (down + up combined).
    private func makeTriangleWaveReps(
        topAngle: Double,
        bottomAngle: Double,
        framesPerRep: Int,
        repCount: Int
    ) -> [BodyPose] {
        var poses: [BodyPose] = []
        var frameIndex = 0
        let halfFrames = framesPerRep / 2

        // Lead-in frames at the top angle so the IIR smoother has settled data.
        for _ in 0..<3 {
            poses.append(makePose(kneeAngleDegrees: topAngle, timestamp: Double(frameIndex) * frameInterval))
            frameIndex += 1
        }

        for _ in 0..<repCount {
            // Descend from top to bottom.
            for step in 0...halfFrames {
                let fraction = Double(step) / Double(halfFrames)
                let angle = topAngle - (topAngle - bottomAngle) * fraction
                poses.append(makePose(kneeAngleDegrees: angle, timestamp: Double(frameIndex) * frameInterval))
                frameIndex += 1
            }
            // Ascend from bottom back to top.
            for step in 1...halfFrames {
                let fraction = Double(step) / Double(halfFrames)
                let angle = bottomAngle + (topAngle - bottomAngle) * fraction
                poses.append(makePose(kneeAngleDegrees: angle, timestamp: Double(frameIndex) * frameInterval))
                frameIndex += 1
            }
        }

        // Trailing frames at the top angle.
        for _ in 0..<3 {
            poses.append(makePose(kneeAngleDegrees: topAngle, timestamp: Double(frameIndex) * frameInterval))
            frameIndex += 1
        }

        return poses
    }

    // MARK: - Tests

    /// Three full-depth reps (165 -> 85 -> 165) should be detected as 3 reps with no
    /// "Shallow depth" flags, since 85 is well below the shallowThreshold of 120.
    func testThreeFullDepthRepsCountedWithoutShallowFlag() {
        let poses = makeTriangleWaveReps(topAngle: 165, bottomAngle: 85, framesPerRep: 45, repCount: 3)

        let result = service.analyze(poses: poses, exerciseName: "Squat")

        XCTAssertEqual(result.repCount, 3)
        XCTAssertEqual(result.repQualities.count, 3)
        for rep in result.repQualities {
            XCTAssertFalse(rep.flags.contains("Shallow depth"), "Unexpected shallow depth flag for rep \(rep.repNumber)")
        }
    }

    /// A rep that only descends to ~121 degrees should still register as a rep
    /// (since 121 < detection threshold of 122.5, the loop enters "inRep"), but
    /// be flagged as "Shallow depth" because 121 > shallowThreshold of 120.
    func testShallowRepFlagsShallowDepth() {
        let poses = makeTriangleWaveReps(topAngle: 165, bottomAngle: 121, framesPerRep: 90, repCount: 1)

        let result = service.analyze(poses: poses, exerciseName: "Squat")

        XCTAssertEqual(result.repCount, 1)
        let rep = try! XCTUnwrap(result.repQualities.first)
        XCTAssertTrue(rep.flags.contains("Shallow depth"), "Expected 'Shallow depth' flag, got \(rep.flags)")
    }

    /// A constant knee angle (no motion) never crosses the detection threshold,
    /// so zero reps should be counted.
    func testConstantAngleProducesNoReps() {
        var poses: [BodyPose] = []
        for i in 0..<60 {
            poses.append(makePose(kneeAngleDegrees: 165, timestamp: Double(i) * frameInterval))
        }

        let result = service.analyze(poses: poses, exerciseName: "Squat")

        XCTAssertEqual(result.repCount, 0)
        XCTAssertTrue(result.repQualities.isEmpty)
    }

    /// A single rep that completes in well under 0.8 seconds should be flagged "Too fast".
    func testVeryFastRepFlagsTooFast() {
        // 6 frames per half (down + up) at 1/30s ≈ 0.2s total motion, well under 0.8s.
        let poses = makeTriangleWaveReps(topAngle: 165, bottomAngle: 85, framesPerRep: 6, repCount: 1)

        let result = service.analyze(poses: poses, exerciseName: "Squat")

        XCTAssertEqual(result.repCount, 1)
        let rep = try! XCTUnwrap(result.repQualities.first)
        XCTAssertTrue(rep.flags.contains("Too fast"), "Expected 'Too fast' flag, got \(rep.flags)")
        XCTAssertLessThan(rep.durationSeconds, 0.8)
    }
}
