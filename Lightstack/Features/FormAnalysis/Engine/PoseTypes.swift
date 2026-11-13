import Foundation

// Pure-logic pose types for the form engine. No camera, Vision or UI imports.

enum BodyJoint: String, CaseIterable, Codable, Hashable {
    case nose, neck
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}

enum BodySide: String, Codable {
    case left, right

    var other: BodySide { self == .left ? .right : .left }
}

/// Normalized (0-1) image coordinates, origin top-left, y down.
struct PosePoint: Codable, Equatable {
    var x: Double
    var y: Double
    var confidence: Double
}

struct PoseFrame: Codable, Equatable {
    var time: TimeInterval
    var joints: [BodyJoint: PosePoint]
}

struct PoseTrack: Codable, Equatable {
    var frames: [PoseFrame]
    /// Width / height of the upright image.
    var aspectRatio: Double
}

/// Which joint angle carries the rep for a movement.
enum JointAngle: String, Codable, CaseIterable {
    case elbow      // shoulder-elbow-wrist
    case shoulder   // hip-shoulder-elbow (arm raise away from torso)
    case knee       // hip-knee-ankle
    case hip        // shoulder-hip-knee

    func joints(_ side: BodySide) -> (BodyJoint, BodyJoint, BodyJoint) {
        let l = side == .left
        switch self {
        case .elbow:    return l ? (.leftShoulder, .leftElbow, .leftWrist) : (.rightShoulder, .rightElbow, .rightWrist)
        case .shoulder: return l ? (.leftHip, .leftShoulder, .leftElbow) : (.rightHip, .rightShoulder, .rightElbow)
        case .knee:     return l ? (.leftHip, .leftKnee, .leftAnkle) : (.rightHip, .rightKnee, .rightAnkle)
        case .hip:      return l ? (.leftShoulder, .leftHip, .leftKnee) : (.rightShoulder, .rightHip, .rightKnee)
        }
    }

    /// Plain-English name of the body part the camera must see for this angle.
    var visibleBodyPart: String {
        switch self {
        case .elbow: return "arms"
        case .shoulder: return "arms and hips"
        case .knee: return "legs"
        case .hip: return "torso and legs"
        }
    }
}

enum PoseGeometry {
    /// Minimum confidence for a joint to count as seen when detecting reps.
    static let visibleConfidence = 0.2

    /// Angle at `b` between rays b->a and b->c, in degrees (0...180). x is scaled by the
    /// aspect ratio first so the angle is geometrically correct.
    static func angle(_ a: PosePoint, _ b: PosePoint, _ c: PosePoint, aspect: Double) -> Double {
        let v1x = (a.x - b.x) * aspect, v1y = a.y - b.y
        let v2x = (c.x - b.x) * aspect, v2y = c.y - b.y
        let cross = abs(v1x * v2y - v1y * v2x)
        let dot = v1x * v2x + v1y * v2y
        return atan2(cross, dot) * 180 / .pi
    }

    /// Visible joint, or nil. A missing joint is never treated as (0,0).
    static func point(_ frame: PoseFrame, _ joint: BodyJoint, minConfidence: Double = visibleConfidence) -> PosePoint? {
        guard let p = frame.joints[joint], p.confidence >= minConfidence else { return nil }
        return p
    }

    /// Angle for one side in one frame, or nil when any of the three joints isn't visible.
    static func angle(in frame: PoseFrame, kind: JointAngle, side: BodySide, aspect: Double,
                      minConfidence: Double = visibleConfidence) -> Double? {
        let (ja, jb, jc) = kind.joints(side)
        guard let a = point(frame, ja, minConfidence: minConfidence),
              let b = point(frame, jb, minConfidence: minConfidence),
              let c = point(frame, jc, minConfidence: minConfidence) else { return nil }
        return angle(a, b, c, aspect: aspect)
    }
}

/// What kind of signal carried the reps.
enum SignalKind: String, Codable {
    /// A joint angle in degrees (unsigned, 2D).
    case angle
    /// The working limb's end joint relative to its root, projected on its main axis of motion,
    /// in percent of a stable body length. Moves one way through a rep even when angles fold.
    case displacement
}

/// Which limb's end joint is tracked relative to its root for the displacement signal.
enum DisplacementLimb: String, Codable {
    case arm     // wrist relative to same-side shoulder
    case leg     // ankle relative to same-side hip
    case trunk   // same-side shoulder relative to same-side hip

    func joints(_ side: BodySide) -> (root: BodyJoint, end: BodyJoint) {
        let l = side == .left
        switch self {
        case .arm: return l ? (.leftShoulder, .leftWrist) : (.rightShoulder, .rightWrist)
        case .leg: return l ? (.leftHip, .leftAnkle) : (.rightHip, .rightAnkle)
        case .trunk: return l ? (.leftHip, .leftShoulder) : (.rightHip, .rightShoulder)
        }
    }
}
