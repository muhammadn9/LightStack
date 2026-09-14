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
                        (pose.confidences[a] ?? 0) > 0.15,
                        (pose.confidences[b] ?? 0) > 0.15
                    else { continue }

                    var path = Path()
                    path.move(to: ptA)
                    path.addLine(to: ptB)
                    ctx.stroke(path, with: .color(.green.opacity(0.75)), lineWidth: 2.5)
                }

                // Draw joints
                for (name, _) in pose.joints {
                    guard (pose.confidences[name] ?? 0) > 0.15,
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
    ///
    /// The camera preview uses `.resizeAspectFill` with a portrait 9:16 buffer, so the
    /// image is scaled up to fill the view and cropped on one axis. We replicate that
    /// scaling/offset here so skeleton points line up with the displayed video.
    private func convert(
        joint: VNHumanBodyPoseObservation.JointName,
        pose: BodyPose,
        size: CGSize
    ) -> CGPoint? {
        guard let p = pose.joints[joint] else { return nil }

        let imageAspect: CGFloat = 9.0 / 16.0
        let viewAspect = size.width / size.height
        var drawn = size
        var offset = CGPoint.zero
        if viewAspect > imageAspect {            // view wider → fill width, crop top/bottom
            drawn = CGSize(width: size.width, height: size.width / imageAspect)
            offset.y = (drawn.height - size.height) / 2
        } else {                                  // view taller → fill height, crop sides
            drawn = CGSize(width: size.height * imageAspect, height: size.height)
            offset.x = (drawn.width - size.width) / 2
        }

        return CGPoint(
            x: p.x * drawn.width - offset.x,           // no mirror — .leftMirrored handles it
            y: (1 - p.y) * drawn.height - offset.y     // flip Y (Vision y=0=bottom, SwiftUI y=0=top)
        )
    }
}
