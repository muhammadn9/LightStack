import Foundation
@testable import Lightstack

/// Reads the pose fixture format (`exercise`, `aspectRatio`, `note`, `frames[{t, j{joint:[x,y,c]}}]`).
/// Extra keys such as the shared-data `analysis` object are ignored.
enum PoseFixtureLoader {
    private struct Fixture: Decodable {
        struct Frame: Decodable { let t: Double; let j: [String: [Double]] }
        let exercise: String?
        let aspectRatio: Double
        let frames: [Frame]
    }

    static func decode(_ data: Data) throws -> (exercise: String?, track: PoseTrack) {
        let fx = try JSONDecoder().decode(Fixture.self, from: data)
        let frames = fx.frames.map { f -> PoseFrame in
            var joints: [BodyJoint: PosePoint] = [:]
            for (key, v) in f.j {
                if let joint = BodyJoint(rawValue: key), v.count >= 3 {
                    joints[joint] = PosePoint(x: v[0], y: v[1], confidence: v[2])
                }
            }
            return PoseFrame(time: f.t, joints: joints)
        }
        return (fx.exercise, PoseTrack(frames: frames, aspectRatio: fx.aspectRatio))
    }
}
