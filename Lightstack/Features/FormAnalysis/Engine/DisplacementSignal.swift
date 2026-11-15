import Foundation

/// Endpoint-displacement rep signal: the working limb's end joint relative to its root joint, in
/// aspect-corrected image space, divided by a body length that is stable over the clip, then projected on
/// the principal axis of that motion (2x2 PCA). Unlike a joint angle it does not fold when the limb
/// crosses the torso line or points at the camera.
enum DisplacementSignal {

    struct Result {
        /// Percent of body scale per frame; NaN where the joints were not visible.
        let values: [Double]
        /// Fraction of the span's frames in which both joints (and the scale) were visible.
        let visibility: Double
    }

    /// Median torso length (shoulder-mid to hip-mid); falls back to shoulder width, then hip-knee length.
    static func bodyScale(frames: [PoseFrame], span: ClosedRange<Int>, aspect: Double) -> Double? {
        func mid(_ f: PoseFrame, _ a: BodyJoint, _ b: BodyJoint) -> (Double, Double)? {
            let pts = [a, b].compactMap { PoseGeometry.point(f, $0) }
            guard !pts.isEmpty else { return nil }
            return (pts.map(\.x).reduce(0, +) / Double(pts.count), pts.map(\.y).reduce(0, +) / Double(pts.count))
        }
        var torso: [Double] = [], shoulderWidth: [Double] = [], thigh: [Double] = []
        for i in span {
            let f = frames[i]
            if let s = mid(f, .leftShoulder, .rightShoulder), let h = mid(f, .leftHip, .rightHip) {
                torso.append(hypot((s.0 - h.0) * aspect, s.1 - h.1))
            }
            if let l = PoseGeometry.point(f, .leftShoulder), let r = PoseGeometry.point(f, .rightShoulder) {
                shoulderWidth.append(hypot((l.x - r.x) * aspect, l.y - r.y))
            }
            for (h, k) in [(BodyJoint.leftHip, BodyJoint.leftKnee), (.rightHip, .rightKnee)] {
                if let a = PoseGeometry.point(f, h), let b = PoseGeometry.point(f, k) {
                    thigh.append(hypot((a.x - b.x) * aspect, a.y - b.y))
                }
            }
        }
        let minSamples = max(5, span.count / 10)
        for list in [torso, shoulderWidth, thigh] where list.count >= minSamples {
            let m = RepDetector.median(list)
            if m > 0.02 { return m }
        }
        return nil
    }

    static func compute(limb: DisplacementLimb, side: BodySide, frames: [PoseFrame],
                        span: ClosedRange<Int>, aspect: Double, scale: Double) -> Result {
        let (rootJoint, endJoint) = limb.joints(side)
        var vectors = [(Double, Double)?](repeating: nil, count: frames.count)
        var xs: [Double] = [], ys: [Double] = []
        for i in span {
            guard let root = PoseGeometry.point(frames[i], rootJoint),
                  let end = PoseGeometry.point(frames[i], endJoint) else { continue }
            let vx = (end.x - root.x) * aspect / scale, vy = (end.y - root.y) / scale
            vectors[i] = (vx, vy)
            xs.append(vx); ys.append(vy)
        }
        let visibility = Double(xs.count) / Double(span.count)
        var values = [Double](repeating: .nan, count: frames.count)
        guard xs.count >= 10 else { return Result(values: values, visibility: visibility) }

        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var a = 0.0, b = 0.0, c = 0.0
        for k in xs.indices {
            let dx = xs[k] - mx, dy = ys[k] - my
            a += dx * dx; b += dx * dy; c += dy * dy
        }
        // Major axis of the 2x2 covariance; sign fixed so the result is deterministic.
        let theta = 0.5 * atan2(2 * b, a - c)
        var ex = cos(theta), ey = sin(theta)
        if abs(ex) >= abs(ey) ? ex < 0 : ey < 0 { ex = -ex; ey = -ey }
        for i in span {
            guard let v = vectors[i] else { continue }
            values[i] = ((v.0 - mx) * ex + (v.1 - my) * ey) * 100
        }
        return Result(values: values, visibility: visibility)
    }
}
