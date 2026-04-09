import Foundation
import Vision

/// A single-frame body pose snapshot from VNHumanBodyPoseObservation.
struct BodyPose {
    let timestamp: TimeInterval
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let confidences: [VNHumanBodyPoseObservation.JointName: Float]
}

extension BodyPose {
    /// Returns the angle in degrees at the middle joint B of three points A-B-C.
    /// Returns nil if any joint is missing or has confidence below `minConfidence`.
    func angle(
        from a: VNHumanBodyPoseObservation.JointName,
        through b: VNHumanBodyPoseObservation.JointName,
        to c: VNHumanBodyPoseObservation.JointName,
        minConfidence: Float = 0.3
    ) -> Double? {
        guard
            let pa = joints[a], (confidences[a] ?? 0) >= minConfidence,
            let pb = joints[b], (confidences[b] ?? 0) >= minConfidence,
            let pc = joints[c], (confidences[c] ?? 0) >= minConfidence
        else { return nil }

        let v1 = CGVector(dx: pa.x - pb.x, dy: pa.y - pb.y)
        let v2 = CGVector(dx: pc.x - pb.x, dy: pc.y - pb.y)
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let cross = v1.dx * v2.dy - v1.dy * v2.dx
        return abs(atan2(cross, dot) * 180 / .pi)
    }
}
