import Foundation
import simd

/// A single-frame 3D body pose from VNDetectHumanBodyPose3DRequest (iOS 17+).
struct BodyPose3D {
    let timestamp: TimeInterval
    let joints: [String: simd_float3]   // joint name → position in meters (camera space)
}
