import SwiftUI

/// Bones and joints drawn over a camera preview or a video replay. Independent of the camera: it only
/// needs the frame, the real aspect ratio of the image underneath (aspect-fill) and which joints to highlight.
struct SkeletonOverlayView: View {

    let frame: PoseFrame?
    let aspectRatio: Double
    let highlighted: Set<BodyJoint>

    static let bones: [(BodyJoint, BodyJoint)] = [
        (.nose, .neck),
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
    ]

    var body: some View {
        Canvas { context, size in
            guard let frame else { return }
            func point(_ joint: BodyJoint) -> CGPoint? {
                guard let p = PoseGeometry.point(frame, joint) else { return nil }
                return Self.point(for: p, aspectRatio: aspectRatio, in: size)
            }

            for (a, b) in Self.bones {
                guard let pa = point(a), let pb = point(b) else { continue }
                let on = highlighted.contains(a) && highlighted.contains(b)
                var path = Path()
                path.move(to: pa)
                path.addLine(to: pb)
                context.stroke(path,
                               with: .color(on ? AppTheme.accent : Color.white.opacity(0.55)),
                               style: StrokeStyle(lineWidth: on ? 6 : 3, lineCap: .round))
            }
            for joint in BodyJoint.allCases {
                guard let p = point(joint) else { continue }
                let on = highlighted.contains(joint)
                let r: CGFloat = on ? 8 : 5
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                context.fill(dot, with: .color(on ? AppTheme.accent : Color.white.opacity(0.7)))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// Maps a normalized image point (top-left origin) into a view of `size` that shows the image with
    /// aspect-fill: the image is scaled until it covers the view and centred, so the overflow is cropped.
    static func point(for p: PosePoint, aspectRatio: Double, in size: CGSize) -> CGPoint {
        let aspect = aspectRatio > 0 ? aspectRatio : 9.0 / 16.0
        // The image is `aspect` wide and 1 tall in its own units.
        let scale = max(Double(size.width) / aspect, Double(size.height))
        let shownWidth = aspect * scale, shownHeight = scale
        let offsetX = (Double(size.width) - shownWidth) / 2
        let offsetY = (Double(size.height) - shownHeight) / 2
        return CGPoint(x: offsetX + p.x * shownWidth, y: offsetY + p.y * shownHeight)
    }
}
