import Foundation
import simd
#if canImport(Lightstack)
@testable import Lightstack
#endif

/// Pure-Swift biomechanical sanity checks for guide motions. Returns human-readable issues (empty = clean).
/// Kept free of XCTest so it can also be compiled into a command-line harness.
enum GuideMotionValidator {

    static let sampleCount = 41

    enum Category: String, CaseIterable {
        case joints, lengths, loop, continuity, floor, angles, bend, bar, planted, movement, geometry, template
    }

    struct Issue: CustomStringConvertible {
        let category: Category
        let message: String
        var description: String { "[\(category.rawValue)] \(message)" }
    }

    static func frames(of motion: ExerciseGuideMotion) -> [GuideFrame] {
        (0..<sampleCount).map { motion.frame(at: Float($0) / Float(sampleCount - 1)) }
    }

    static func angleDegrees(_ a: V3, _ b: V3) -> Float {
        let la = simd_length(a), lb = simd_length(b)
        guard la > 1e-6, lb > 1e-6 else { return 0 }
        let c = max(-1, min(1, simd_dot(a, b) / (la * lb)))
        return acos(c) * 180 / .pi
    }

    static func interiorAngle(_ p: FigurePose, _ a: GuideJoint, _ mid: GuideJoint, _ c: GuideJoint) -> Float {
        angleDegrees(p.position(a) - p.position(mid), p.position(c) - p.position(mid))
    }

    static func distanceToSegment(_ p: V3, _ a: V3, _ b: V3) -> Float {
        let ab = b - a
        let t = max(0, min(1, simd_dot(p - a, ab) / max(simd_dot(ab, ab), 1e-9)))
        return simd_length(p - (a + ab * t))
    }

    static func barProp(in frame: GuideFrame) -> (center: V3, axis: V3)? {
        for prop in frame.props {
            switch prop {
            case let .barbell(c, a, _, _): return (c, a)
            case let .ezBar(c, a): return (c, a)
            default: continue
            }
        }
        return nil
    }

    // MARK: Segments

    private typealias Segment = (String, GuideJoint, GuideJoint, Float)

    private static let segments: [Segment] = {
        typealias P = FigureProportions
        var out: [Segment] = []
        out.append(("left thigh", .leftHip, .leftKnee, P.thigh))
        out.append(("right thigh", .rightHip, .rightKnee, P.thigh))
        out.append(("left shin", .leftKnee, .leftAnkle, P.shin))
        out.append(("right shin", .rightKnee, .rightAnkle, P.shin))
        out.append(("left foot", .leftAnkle, .leftToe, P.foot))
        out.append(("right foot", .rightAnkle, .rightToe, P.foot))
        out.append(("left upper arm", .leftShoulder, .leftElbow, P.upperArm))
        out.append(("right upper arm", .rightShoulder, .rightElbow, P.upperArm))
        out.append(("left forearm", .leftElbow, .leftWrist, P.forearm))
        out.append(("right forearm", .rightElbow, .rightWrist, P.forearm))
        out.append(("left hand", .leftWrist, .leftHand, P.hand))
        out.append(("right hand", .rightWrist, .rightHand, P.hand))
        out.append(("lower spine", .pelvis, .spineMid, P.spineLower))
        out.append(("upper spine", .spineMid, .chest, P.spineUpper))
        out.append(("neck", .chest, .neck, P.neck))
        out.append(("head", .neck, .head, P.head))
        out.append(("shoulder width", .leftShoulder, .rightShoulder, P.shoulderHalfWidth * 2))
        out.append(("hip width", .leftHip, .rightHip, P.hipHalfWidth * 2))
        return out
    }()

    // MARK: Validation

    static func validate(_ motion: ExerciseGuideMotion) -> [String] {
        issues(for: motion).map { "\($0.description) \(motion.exerciseName)" }
    }

    static func issues(for motion: ExerciseGuideMotion) -> [Issue] {
        var issues: [Issue] = []
        func fail(_ c: Category, _ s: String) { issues.append(Issue(category: c, message: "\(motion.exerciseName): \(s)")) }
        let fs = frames(of: motion)
        let poses = fs.map(\.pose)
        let traits = motion.traits

        // 1. joints present, finite, segment lengths.
        for (i, f) in fs.enumerated() {
            for j in GuideJoint.allCases {
                guard let p = f.pose.joints[j] else { fail(.joints, "joint \(j) missing at sample \(i)"); continue }
                if !(p.x.isFinite && p.y.isFinite && p.z.isFinite) { fail(.joints, "joint \(j) not finite at sample \(i)") }
            }
        }
        var lengthIssueSegments = Set<String>()
        for (i, p) in poses.enumerated() {
            for (name, a, b, expected) in segments {
                let l = simd_length(p.position(a) - p.position(b))
                if abs(l - expected) / expected > 0.015, lengthIssueSegments.insert(name).inserted {
                    fail(.lengths, "\(name) length \(l) vs \(expected) at sample \(i)")
                }
            }
        }

        // 2. loop closure + continuity.
        for j in GuideJoint.allCases {
            let d = simd_length(poses[0].position(j) - poses[sampleCount - 1].position(j))
            if d > 0.002 { fail(.loop, "loop gap \(j) = \(d * 1000) mm"); break }
        }
        var worstStep: Float = 0
        var worstJoint = GuideJoint.pelvis
        var worstIndex = 0
        for i in 1..<sampleCount {
            for j in GuideJoint.allCases {
                let d = simd_length(poses[i].position(j) - poses[i - 1].position(j))
                if d > worstStep { worstStep = d; worstJoint = j; worstIndex = i }
            }
        }
        if worstStep > traits.maxStep { fail(.continuity, "step \(worstStep) m of \(worstJoint) at sample \(worstIndex) exceeds \(traits.maxStep)") }

        // 3. floor, interior angles, bend direction.
        var floorReported = false, angleReported = Set<String>(), bendReported = Set<String>()
        for (i, p) in poses.enumerated() {
            for j in GuideJoint.allCases where p.position(j).y < -0.005 && !floorReported {
                floorReported = true
                fail(.floor, "\(j) below floor (\(p.position(j).y)) at sample \(i)")
            }
            let limbs: [(String, GuideJoint, GuideJoint, GuideJoint, Bool)] = [
                ("left knee", .leftHip, .leftKnee, .leftAnkle, true), ("right knee", .rightHip, .rightKnee, .rightAnkle, true),
                ("left elbow", .leftShoulder, .leftElbow, .leftWrist, false), ("right elbow", .rightShoulder, .rightElbow, .rightWrist, false)
            ]
            for (name, a, m, c, isKnee) in limbs {
                let ang = interiorAngle(p, a, m, c)
                if (ang < 25 || ang > 180.5), angleReported.insert(name).inserted { fail(.angles, "\(name) interior angle \(ang) at sample \(i)") }
                let t = p.position(m) - p.position(a)
                let s = p.position(c) - p.position(m)
                let n = simd_cross(t, s)
                if isKnee {
                    let axis = p.pelvisRotation.act(V3(1, 0, 0))
                    if simd_dot(n, axis) < -0.002, bendReported.insert(name).inserted { fail(.bend, "\(name) bends backwards at sample \(i)") }
                } else {
                    // Elbow: only meaningful when the arm hangs near the body and flexes about the sideways axis.
                    let chestX = p.chestRotation.act(V3(1, 0, 0))
                    let chestDown = p.chestRotation.act(V3(0, -1, 0))
                    let un = simd_normalize(t)
                    if simd_dot(un, chestDown) > 0.5, simd_length(n) > 1e-4,
                       abs(simd_dot(simd_normalize(n), chestX)) > 0.8,
                       simd_dot(simd_normalize(n), chestX) > 0.1, bendReported.insert(name).inserted {
                        fail(.bend, "\(name) bends backwards at sample \(i)")
                    }
                }
            }
        }

        // 4. bilateral bar.
        if traits.bilateralBar {
            var widths: [Float] = []
            for (i, f) in fs.enumerated() {
                guard let bar = barProp(in: f) else { fail(.bar, "no bar prop at sample \(i)"); break }
                let axis = simd_normalize(bar.axis)
                if abs(axis.y) > sin(2 * .pi / 180) { fail(.bar, "bar not level at sample \(i)"); break }
                for hand in [GuideJoint.leftHand, .rightHand] {
                    let h = f.pose.position(hand) - bar.center
                    let off = simd_length(h - axis * simd_dot(h, axis))
                    if off > 0.015 { fail(.bar, "\(hand) \(off * 100) cm off the bar at sample \(i)"); break }
                }
                widths.append(simd_length(f.pose.position(.leftHand) - f.pose.position(.rightHand)))
            }
            if let lo = widths.min(), let hi = widths.max(), hi - lo > 0.01 { fail(.bar, "grip width varies \((hi - lo) * 100) cm") }
        }

        // 5. feet planted.
        if traits.feetPlanted {
            for a in [GuideJoint.leftAnkle, .rightAnkle] {
                let ps = poses.map { $0.position(a) }
                let d = ps.map { simd_length($0 - ps[0]) }.max() ?? 0
                if d > 0.01 { fail(.planted, "\(a) moves \(d * 100) cm but feet should be planted") }
            }
        }

        // 6. the motion moves.
        if !traits.isometric {
            var path: Float = 0
            for i in 1..<sampleCount {
                path += simd_length(poses[i].position(traits.drivingJoint) - poses[i - 1].position(traits.drivingJoint))
            }
            if path < traits.minPath { fail(.movement, "driving joint \(traits.drivingJoint) path only \(path) m") }
        }

        // Geometry: limbs must not pass through pads/frames, the torso, or each other.
        var boxReported = false, torsoReported = Set<String>(), crossReported = Set<String>()
        for (i, f) in fs.enumerated() {
            let p = f.pose
            let limbPairs: [(GuideJoint, GuideJoint)] = [
                (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist), (.leftWrist, .leftHand),
                (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.rightWrist, .rightHand),
                (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.leftAnkle, .leftToe),
                (.rightHip, .rightKnee), (.rightKnee, .rightAnkle), (.rightAnkle, .rightToe)
            ]
            var pts: [V3] = []
            for (a, b) in limbPairs {
                let pa = p.position(a), pb = p.position(b)
                for k in 0...4 where !(a == .leftShoulder || a == .rightShoulder || a == .leftHip || a == .rightHip) || k > 0 {
                    pts.append(pa + (pb - pa) * (Float(k) / 4))
                }
            }
            for prop in f.props {
                guard case let .box(c, size, rot, kind) = prop, kind != .weightStack else { continue }
                let half = size / 2 - V3(repeating: 0.025)
                for pt in pts where !boxReported {
                    let local = rot.inverse.act(pt - c)
                    if abs(local.x) < half.x, abs(local.y) < half.y, abs(local.z) < half.z {
                        boxReported = true
                        fail(.geometry, "limb point inside \(kind) box at sample \(i): \(pt)")
                    }
                }
            }
            let torsoA = p.position(.pelvis), torsoB = p.position(.chest)
            for j in [GuideJoint.leftElbow, .rightElbow, .leftWrist, .rightWrist] {
                let d = distanceToSegment(p.position(j), torsoA, torsoB)
                if d < 0.07, torsoReported.insert("\(j)").inserted { fail(.geometry, "\(j) only \(d * 100) cm from the torso at sample \(i)") }
            }
            for j in [GuideJoint.leftKnee, .rightKnee, .leftAnkle, .rightAnkle] {
                let d = distanceToSegment(p.position(j), torsoA, torsoB)
                if d < 0.10, torsoReported.insert("\(j)").inserted { fail(.geometry, "\(j) only \(d * 100) cm from the torso at sample \(i)") }
            }
            for (a, b, minD) in [(GuideJoint.leftKnee, GuideJoint.rightKnee, Float(0.07)), (.leftAnkle, .rightAnkle, 0.07),
                                 (.leftElbow, .rightElbow, 0.07), (.leftWrist, .rightWrist, 0.05)] {
                let d = simd_length(p.position(a) - p.position(b))
                if d < minD, crossReported.insert("\(a)").inserted { fail(.geometry, "\(a) and \(b) only \(d * 100) cm apart at sample \(i)") }
            }
        }

        // 7. template specific.
        switch traits.template {
        case .squat:
            if let bottom = poses.min(by: { $0.position(.pelvis).y < $1.position(.pelvis).y }) {
                let kneeY = (bottom.position(.leftKnee).y + bottom.position(.rightKnee).y) / 2
                if bottom.position(.pelvis).y > kneeY + 0.05 { fail(.template, "squat bottom hip \(bottom.position(.pelvis).y) above knee \(kneeY) + 0.05") }
            }
            for (i, p) in poses.enumerated() {
                for (k, t) in [(GuideJoint.leftKnee, GuideJoint.leftToe), (.rightKnee, .rightToe)] where p.position(k).z > p.position(t).z + 0.08 {
                    fail(.template, "\(k) z \(p.position(k).z) past toe \(p.position(t).z) at sample \(i)")
                    break
                }
            }
        case .deadlift:
            for (i, p) in poses.enumerated() {
                let a = p.position(.spineMid) - p.position(.pelvis)
                let b = p.position(.chest) - p.position(.spineMid)
                if angleDegrees(a, b) > 6 { fail(.template, "deadlift spine bends \(angleDegrees(a, b)) deg at sample \(i)"); break }
            }
            for (i, f) in fs.enumerated() {
                guard let bar = barProp(in: f) else { break }
                let mid = (f.pose.position(.leftAnkle) + f.pose.position(.leftToe) + f.pose.position(.rightAnkle) + f.pose.position(.rightToe)) / 4
                let d = simd_length(V3(bar.center.x - mid.x, 0, bar.center.z - mid.z))
                if d > 0.10 { fail(.template, "deadlift bar \(d * 100) cm from mid-foot at sample \(i)"); break }
            }
        case .benchPress:
            if let bottom = fs.min(by: { (barProp(in: $0)?.center.y ?? 9) < (barProp(in: $1)?.center.y ?? 9) }) {
                for (e, w) in [(GuideJoint.leftElbow, GuideJoint.leftWrist), (.rightElbow, .rightWrist)] {
                    let fore = bottom.pose.position(w) - bottom.pose.position(e)
                    let a = angleDegrees(fore, V3(0, 1, 0))
                    if a > 15 { fail(.template, "bench forearm \(a) deg from vertical at the bottom") }
                }
            }
            for f in fs { if let bar = barProp(in: f), abs(bar.center.x) > 0.01 { fail(.template, "bench bar off the midline"); break } }
        case .curl:
            for (s, e) in [(GuideJoint.leftShoulder, GuideJoint.leftElbow), (.rightShoulder, .rightElbow)] {
                let angles = poses.map { p -> Float in
                    angleDegrees(p.position(e) - p.position(s), p.position(.chest) - p.position(.pelvis))
                }
                if let lo = angles.min(), let hi = angles.max(), hi - lo > 15 { fail(.template, "curl upper arm swings \(hi - lo) deg relative to torso") }
            }
        case .lateralRaise:
            var top: Float = -9
            for p in poses {
                top = max(top, p.position(.leftWrist).y - p.position(.leftShoulder).y)
            }
            if top < -0.08 || top > 0.02 { fail(.template, "lateral raise wrist reaches \(top) m relative to shoulder, expected -0.08...0.02") }
        case .pullUp:
            for h in [GuideJoint.leftHand, .rightHand] {
                let ps = poses.map { $0.position(h) }
                let d = ps.map { simd_length($0 - ps[0]) }.max() ?? 0
                if d > 0.01 { fail(.template, "\(h) moves \(d * 100) cm on a pull-up") }
            }
            let ys = poses.map { $0.position(.chest).y }
            if let lo = ys.min(), let hi = ys.max(), hi - lo < 0.35 { fail(.template, "pull-up chest rises only \(hi - lo) m") }
        case .overheadPress:
            if let top = fs.max(by: { (barProp(in: $0)?.center.y ?? -9) < (barProp(in: $1)?.center.y ?? -9) }),
               let bar = barProp(in: top) {
                let dz = abs(bar.center.z - top.pose.position(.chest).z)
                if dz > 0.08 { fail(.template, "overhead press lockout bar \(dz * 100) cm from the shoulder line") }
            }
        case .other:
            break
        }
        return issues
    }
}
