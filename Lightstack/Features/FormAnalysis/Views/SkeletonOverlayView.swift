import SwiftUI
import Vision

/// Renders joint dots and bone connections over the camera preview.
/// Coordinates are normalized (0-1) from Vision; mirrored on X for front camera.
struct SkeletonOverlayView: View {

    let pose: BodyPose?

    private let bones: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow),    (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),  (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip),      (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee),          (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),        (.rightKnee, .rightAnkle)
    ]

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard let pose else { return }

                // Draw bones
                for (a, b) in bones {
                    guard
                        let ptA = convert(joint: a, pose: pose, size: size),
                        let ptB = convert(joint: b, pose: pose, size: size),
                        (pose.confidences[a] ?? 0) > 0.3,
                        (pose.confidences[b] ?? 0) > 0.3
                    else { continue }

                    var path = Path()
                    path.move(to: ptA)
                    path.addLine(to: ptB)
                    ctx.stroke(path, with: .color(.green.opacity(0.75)), lineWidth: 2.5)
                }

                // Draw joints
                for (name, _) in pose.joints {
                    guard (pose.confidences[name] ?? 0) > 0.3,
                          let pt = convert(joint: name, pose: pose, size: size)
                    else { continue }
                    let rect = CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.green))
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Coordinate Conversion

    /// Vision: x=0 left, y=0 bottom, normalized. SwiftUI: x=0 left, y=0 top.
    /// .leftMirrored orientation passed to VNImageRequestHandler already corrects for
    /// front camera landscape buffers, so no X-mirror needed here.
    private func convert(
        joint: VNHumanBodyPoseObservation.JointName,
        pose: BodyPose,
        size: CGSize
    ) -> CGPoint? {
        guard let p = pose.joints[joint] else { return nil }
        return CGPoint(
            x: p.x * size.width,          // no mirror — .leftMirrored handles it
            y: (1 - p.y) * size.height    // flip Y (Vision y=0=bottom, SwiftUI y=0=top)
        )
    }
}
