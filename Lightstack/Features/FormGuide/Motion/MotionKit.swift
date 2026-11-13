import Foundation
import simd

/// Easing and small helpers shared by every motion template.
enum Ease {
    static func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }
    static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
    static func lerp(_ a: V3, _ b: V3, _ t: Float) -> V3 { a + (b - a) * t }

    /// Smooth S-curve 0...1 (zero velocity at both ends).
    static func smooth(_ x: Float) -> Float {
        let t = clamp01(x)
        return t * t * (3 - 2 * t)
    }

    /// Smooth ramp that is 0 before `from` and 1 after `to`.
    static func ramp(_ t: Float, from: Float, to: Float) -> Float {
        smooth((t - from) / max(to - from, 1e-6))
    }

    /// 0 -> 1 -> 0 over the rep with an optional hold (fraction of the rep) at the peak.
    static func profile(_ t: Float, hold: Float = 0) -> Float {
        let seg = (1 - hold) / 2
        if t < seg { return smooth(t / seg) }
        if t < seg + hold { return 1 }
        return smooth(1 - (t - seg - hold) / seg)
    }

    /// Asymmetric profile: peak reached at `peak` (0...1), smooth both sides.
    static func profile(_ t: Float, peak: Float) -> Float {
        t < peak ? smooth(t / peak) : smooth(1 - (t - peak) / (1 - peak))
    }

    /// 0 -> 1 -> 0 cosine wave (no holds).
    static func wave(_ t: Float) -> Float { 0.5 - 0.5 * cos(2 * .pi * t) }

    static func rad(_ degrees: Float) -> Float { degrees * .pi / 180 }
}

func mirrorX(_ v: V3) -> V3 { V3(-v.x, v.y, v.z) }

func degrees(_ r: Float) -> Float { r * 180 / .pi }

// MARK: - PoseSpec authoring helpers

extension PoseSpec {
    /// Standing tall, feet flat, hip-width-ish stance, arms hanging.
    static func standing(stance: Float = 0.13, toeOut: Float = 10, pelvisY: Float = 0.925, pelvisZ: Float = 0,
                         ankleZ: Float = 0) -> PoseSpec {
        var s = PoseSpec()
        s.pelvis = V3(0, pelvisY, pelvisZ)
        s.leftLeg = FigureSolver.flatLeg(side: 1, x: stance, z: ankleZ, toeOut: toeOut)
        s.rightLeg = FigureSolver.flatLeg(side: -1, x: stance, z: ankleZ, toeOut: toeOut)
        return s
    }

    /// Both hands on a bar: left hand on +X, right on -X. `pole` is for the left elbow (mirrored for the right).
    mutating func gripBar(center: V3, axis: V3 = V3(1, 0, 0), halfGrip: Float, handDir: V3?, pole: V3) {
        let a = FigureSolver.safeNormalize(axis, fallback: V3(1, 0, 0))
        leftArm = .reach(hand: center + a * halfGrip, pole: pole, handDir: handDir)
        rightArm = .reach(hand: center - a * halfGrip, pole: mirrorX(pole), handDir: handDir.map(mirrorX))
        leftGrip = a
        rightGrip = a
    }

    /// Symmetric chest-frame FK arms.
    mutating func armsFK(upper: V3, flex: Float, bend: V3) {
        leftArm = .fk(upper: upper, elbowFlex: flex, bend: bend)
        rightArm = .fk(upper: mirrorX(upper), elbowFlex: flex, bend: mirrorX(bend))
    }

    /// Symmetric world-space FK arms (upper direction given for the left arm).
    mutating func armsFKWorld(upper: V3, flex: Float, bend: V3) {
        leftArm = .fkWorld(upper: upper, elbowFlex: flex, bend: bend)
        rightArm = .fkWorld(upper: mirrorX(upper), elbowFlex: flex, bend: mirrorX(bend))
    }

    mutating func plantFeet(leftAnkle: V3, rightAnkle: V3, leftPole: V3, rightPole: V3,
                            leftDir: V3? = nil, rightDir: V3? = nil, toeOut: Float = 10) {
        leftLeg = .plant(ankle: leftAnkle, pole: leftPole, footDir: leftDir ?? FigureSolver.footDir(side: 1, toeOutDegrees: toeOut))
        rightLeg = .plant(ankle: rightAnkle, pole: rightPole, footDir: rightDir ?? FigureSolver.footDir(side: -1, toeOutDegrees: toeOut))
    }
}

// MARK: - Props

enum Props {
    static let barLength: Float = 2.2
    static let plateRadius: Float = 0.225

    static func barbell(_ center: V3, plates: Bool = true) -> GuideProp {
        .barbell(center: center, axis: V3(1, 0, 0), length: barLength, plateRadius: plates ? plateRadius : 0)
    }

    static func box(_ center: V3, _ size: V3, _ rot: simd_quatf = simd_quatf(angle: 0, axis: V3(0, 1, 0)),
                    _ kind: GuideProp.BoxKind = .pad) -> GuideProp {
        .box(center: center, size: size, rotation: rot, kind: kind)
    }

    /// Rotation whose local Y axis is `y` and whose local Z axis is as close to `zHint` as possible.
    static func orient(y: V3, zHint: V3) -> simd_quatf {
        let yy = FigureSolver.safeNormalize(y)
        let z = FigureSolver.safeNormalize(zHint - yy * simd_dot(zHint, yy), fallback: V3(0, 0, 1))
        let x = simd_cross(yy, z)
        return simd_quatf(simd_float3x3(columns: (x, yy, z)))
    }

    static func rod(_ from: V3, _ to: V3, _ radius: Float = 0.025, _ kind: GuideProp.BoxKind = .frame) -> GuideProp {
        .cylinder(from: from, to: to, radius: radius, kind: kind)
    }

    /// Flat bench: pad top at `padTop`, spanning z in [zMin, zMax].
    static func flatBench(padTop: Float = 0.45, zMin: Float = -0.90, zMax: Float = 0.30, width: Float = 0.30) -> [GuideProp] {
        let len = zMax - zMin
        let mid = (zMin + zMax) / 2
        return [
            box(V3(0, padTop - 0.05, mid), V3(width, 0.10, len)),
            rod(V3(0, 0, zMin + 0.12), V3(0, padTop - 0.10, zMin + 0.12), 0.03),
            rod(V3(0, 0, zMax - 0.12), V3(0, padTop - 0.10, zMax - 0.12), 0.03),
            rod(V3(0, 0.02, zMin + 0.05), V3(0, 0.02, zMax - 0.05), 0.025)
        ]
    }

    /// Back pad + seat pad for a lying/reclined figure. `pelvisRot` is the pelvis frame (y = along the spine).
    static func backSupport(pelvis: V3, pelvisRot: simd_quatf, length: Float = 0.85, width: Float = 0.30) -> [GuideProp] {
        let up = pelvisRot.act(V3(0, 1, 0))
        let front = pelvisRot.act(V3(0, 0, 1))
        let center = pelvis + up * (length / 2 - 0.12) - front * 0.14
        var out: [GuideProp] = [box(center, V3(width, length, 0.08), pelvisRot)]
        // Seat pad under the hips.
        let seatTop = pelvis.y - 0.10
        out.append(box(V3(0, seatTop - 0.04, pelvis.z + 0.12), V3(width, 0.08, 0.40)))
        // Frame legs.
        out.append(rod(V3(0, 0, pelvis.z + 0.15), V3(0, seatTop - 0.08, pelvis.z + 0.15), 0.03))
        let backEnd = center - up * (length / 2)
        _ = backEnd
        let top = center + up * (length / 2 - 0.05)
        out.append(rod(V3(0, 0, top.z - 0.10), V3(top.x, max(top.y - 0.10, 0.2), top.z), 0.03))
        out.append(rod(V3(0, 0.02, top.z - 0.1), V3(0, 0.02, pelvis.z + 0.2), 0.025))
        return out
    }

    /// Two rack uprights behind the head end of a bench.
    static func rack(z: Float, height: Float = 1.30, halfWidth: Float = 0.62) -> [GuideProp] {
        [rod(V3(halfWidth, 0, z), V3(halfWidth, height, z), 0.035),
         rod(V3(-halfWidth, 0, z), V3(-halfWidth, height, z), 0.035),
         rod(V3(halfWidth, height - 0.02, z), V3(halfWidth, height - 0.02, z + 0.10), 0.02),
         rod(V3(-halfWidth, height - 0.02, z), V3(-halfWidth, height - 0.02, z + 0.10), 0.02)]
    }

    /// Cable tower: upright post with a pulley point; returns the pulley position too.
    static func tower(x: Float, z: Float, pulleyY: Float) -> [GuideProp] {
        [rod(V3(x, 0, z), V3(x, 2.25, z), 0.04),
         box(V3(x, 0.20, z - 0.15), V3(0.35, 0.40, 0.25), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .weightStack),
         box(V3(x, pulleyY, z), V3(0.10, 0.10, 0.10), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .frame)]
    }

    static func floorMat(center: V3 = V3(0, 0.01, 0), size: SIMD2<Float> = SIMD2<Float>(0.9, 2.0)) -> GuideProp {
        .mat(center: center, size: size)
    }
}
