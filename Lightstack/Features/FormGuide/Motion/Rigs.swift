import Foundation
import simd

/// Reusable body set-ups (lying on a bench, seated) with their bench/seat props.
enum Rigs {

    struct Lying {
        var spec: PoseSpec
        var props: [GuideProp]
        /// Shoulder-line centre.
        var chest: V3
        /// Unit vector from pelvis towards the head.
        var up: V3
        /// Unit vector out of the chest (front of the body).
        var front: V3
    }

    /// Lying on a bench whose back angle is `incline` degrees above horizontal (negative = decline).
    static func lying(incline: Float, pelvisY: Float? = nil, hipWidthFeet: Float = 0.24) -> Lying {
        var s = PoseSpec()
        let theta = -Ease.rad(90 - incline)
        let py = pelvisY ?? (incline < -5 ? 0.80 : 0.55)
        s.pelvis = V3(0, py, 0)
        s.pelvisPitch = theta
        // Shoulder blades pinched back into the pad: the shoulder joints sit lower than the chest line.
        if incline < 5 { s.shoulderLift = -0.05 }
        if abs(incline) < 5 {
            // Slight arch: lift the mid back a little while shoulders and hips stay on the pad.
            s.spineLower = 0.08
            s.spineUpper = -0.12
        }
        let ankleY: Float = incline < -5 ? 0.55 : 0.08
        let ankleZ: Float = incline < -5 ? 0.60 : 0.42
        let footDir: V3 = incline < -5 ? V3(0, 0.55, 0.83) : FigureSolver.footDir(side: 1)
        s.leftLeg = .plant(ankle: V3(hipWidthFeet * 0.85, ankleY, ankleZ), pole: V3(0.35, 1, 0.3), footDir: footDir)
        s.rightLeg = .plant(ankle: V3(-hipWidthFeet * 0.85, ankleY, ankleZ),
                            pole: V3(-0.35, 1, 0.3), footDir: V3(-footDir.x, footDir.y, footDir.z))
        let base = FigureSolver.solve(s)
        let up = simd_normalize(base.position(.chest) - base.position(.pelvis))
        let front = base.pelvisRotation.act(V3(0, 0, 1))
        var props: [GuideProp]
        if abs(incline) < 5 {
            props = Props.flatBench(padTop: py - 0.10)
        } else {
            props = Props.backSupport(pelvis: s.pelvis, pelvisRot: base.pelvisRotation)
            if incline < -5 {
                props.append(Props.rod(V3(-0.22, 0.52, 0.50), V3(0.22, 0.52, 0.50), 0.04, .pad))
                props.append(Props.rod(V3(-0.22, 0.52, 0.70), V3(0.22, 0.52, 0.70), 0.04, .pad))
            }
        }
        return Lying(spec: s, props: props, chest: base.position(.chest), up: up, front: front)
    }

    struct Seated {
        var spec: PoseSpec
        var props: [GuideProp]
    }

    /// Seated on a pad with the back pad leaning `backLean` degrees behind vertical.
    static func seated(seatTop: Float = 0.45, backLean: Float = 0, pelvisZ: Float = 0,
                       ankleX: Float = 0.20, ankleY: Float = 0.08, ankleZ: Float = 0.42,
                       withBackPad: Bool = true) -> Seated {
        var s = PoseSpec()
        s.pelvis = V3(0, seatTop + 0.10, pelvisZ)
        s.pelvisPitch = -Ease.rad(backLean)
        let dir = FigureSolver.footDir(side: 1, toeOutDegrees: 8)
        s.leftLeg = .plant(ankle: V3(ankleX, ankleY, ankleZ), pole: V3(0.2, 1, 0.3), footDir: dir)
        s.rightLeg = .plant(ankle: V3(-ankleX, ankleY, ankleZ), pole: V3(-0.2, 1, 0.3), footDir: V3(-dir.x, dir.y, dir.z))
        let base = FigureSolver.solve(s)
        var props: [GuideProp] = [
            Props.box(V3(0, seatTop - 0.05, pelvisZ + 0.12), V3(0.42, 0.10, 0.50)),
            Props.rod(V3(0, 0, pelvisZ + 0.12), V3(0, seatTop - 0.10, pelvisZ + 0.12), 0.04)
        ]
        if withBackPad {
            let up = base.pelvisRotation.act(V3(0, 1, 0))
            let front = base.pelvisRotation.act(V3(0, 0, 1))
            let length: Float = 0.80
            let center = s.pelvis + up * (length / 2 - 0.12) - front * 0.14
            props.append(Props.box(center, V3(0.40, length, 0.08), base.pelvisRotation))
            props.append(Props.rod(V3(0, 0, pelvisZ - 0.25), V3(0, seatTop - 0.10, pelvisZ - 0.1), 0.03))
        }
        return Seated(spec: s, props: props)
    }
}

extension Rigs {
    /// Standing hip hinge: torso pitched `pitchDegrees` from vertical, feet planted shoulder-width, knees soft.
    static func hinged(pitchDegrees: Float, pelvis: V3, stance: Float = 0.13, ankleZ: Float = 0) -> PoseSpec {
        var s = PoseSpec.standing(stance: stance, pelvisY: pelvis.y, pelvisZ: pelvis.z, ankleZ: ankleZ)
        s.pelvis = pelvis
        s.pelvisPitch = Ease.rad(pitchDegrees)
        return s
    }
}

extension Rigs {
    /// Height of a bar held in straight-ish arms hanging from `shoulder` (hands at x = halfGrip, z = barZ).
    static func hangBarY(shoulder: V3, barZ: Float, halfGrip: Float, reach: Float = 0.545) -> Float {
        let dx = halfGrip - shoulder.x
        let dz = barZ - shoulder.z
        let vertical = sqrt(max(reach * reach - dx * dx - dz * dz, 0.01))
        return shoulder.y - vertical - FigureProportions.hand
    }

    /// Puts a barbell across the upper back (high-bar position) and grips it. Returns the bar centre.
    @discardableResult
    static func holdBackBar(_ s: inout PoseSpec, halfGrip: Float = 0.32, low: Bool = false) -> V3 {
        let base = FigureSolver.solve(s)
        let rot = base.chestRotation
        let bar = base.position(.chest) + rot.act(V3(0, low ? 0.0 : 0.05, -0.10))
        let handDir = rot.act(FigureSolver.safeNormalize(V3(0.25, 1, 0.3)))
        s.gripBar(center: bar, halfGrip: halfGrip, handDir: handDir, pole: rot.act(V3(0.3, -1, -0.5)))
        return bar
    }
}
