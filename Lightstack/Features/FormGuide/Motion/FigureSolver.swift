import Foundation
import simd

typealias V3 = SIMD3<Float>

@inline(__always) func v3(_ x: Float, _ y: Float, _ z: Float) -> V3 { V3(x, y, z) }

/// Fixed mannequin dimensions. Nothing in the solver ever stretches a bone.
enum FigureProportions {
    static let ankleHeight: Float = 0.08
    static let shin: Float = 0.42
    static let thigh: Float = 0.43
    static let hipHalfWidth: Float = 0.09
    static let spineLower: Float = 0.25
    static let spineUpper: Float = 0.25
    static let shoulderHalfWidth: Float = 0.19
    static let upperArm: Float = 0.30
    static let forearm: Float = 0.26
    static let hand: Float = 0.09
    /// Chest (shoulder line centre) to neck.
    static let neck: Float = 0.11
    /// Neck to head centre.
    static let head: Float = 0.11
    static let headRadius: Float = 0.10
    /// Ankle to toe (ball of foot).
    static let foot: Float = 0.20

    static var pelvisStandingHeight: Float { ankleHeight + shin + thigh }
    static var spine: Float { spineLower + spineUpper }
    static var totalHeight: Float { pelvisStandingHeight + spine + neck + head + headRadius }
    /// Pitch (radians) of the ankle-to-toe line when the foot is flat on the floor.
    static var flatFootPitch: Float { asin(ankleHeight / foot) }
}

enum ArmSpec {
    /// Hand grip centre target in world space; elbow bends towards `pole`.
    case reach(hand: V3, pole: V3, handDir: V3?)
    /// Upper arm direction + elbow flexion + bend hint, in the chest frame (x left, y up, z forward).
    case fk(upper: V3, elbowFlex: Float, bend: V3)
    /// Same as `.fk` but with world-space vectors.
    case fkWorld(upper: V3, elbowFlex: Float, bend: V3)
}

enum LegSpec {
    /// Ankle target in world space; knee bends towards `pole`; `footDir` is the unit ankle-to-toe direction.
    case plant(ankle: V3, pole: V3, footDir: V3)
}

/// Compact description of a whole-body posture. Everything is solved from this; limb lengths never change.
struct PoseSpec {
    var pelvis = V3(0, 0.925, 0)
    var pelvisYaw: Float = 0
    var pelvisPitch: Float = 0
    var pelvisRoll: Float = 0
    var spineLower: Float = 0
    var spineUpper: Float = 0
    var spineTwist: Float = 0
    var spineBend: Float = 0
    var headPitch: Float = 0
    /// Vertical shoulder elevation in metres (shrugs). Left/right distance is unchanged.
    var shoulderLift: Float = 0
    var leftArm: ArmSpec = .fk(upper: V3(0.05, -1, 0), elbowFlex: 0.05, bend: V3(0, 0, 1))
    var rightArm: ArmSpec = .fk(upper: V3(-0.05, -1, 0), elbowFlex: 0.05, bend: V3(0, 0, 1))
    var leftLeg: LegSpec = FigureSolver.flatLeg(side: 1)
    var rightLeg: LegSpec = FigureSolver.flatLeg(side: -1)
    var leftGrip = V3(1, 0, 0)
    var rightGrip = V3(1, 0, 0)
}

enum FigureSolver {

    // MARK: Rotation helpers

    static func qx(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: V3(1, 0, 0)) }
    static func qy(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: V3(0, 1, 0)) }
    static func qz(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: V3(0, 0, 1)) }

    static func safeNormalize(_ v: V3, fallback: V3 = V3(0, 1, 0)) -> V3 {
        let l = simd_length(v)
        return l > 1e-6 ? v / l : fallback
    }

    // MARK: Feet

    /// Unit ankle-to-toe direction. `side` +1 left / -1 right; toe-out in degrees; pitch (radians) is toes-down positive.
    static func footDir(side: Float, toeOutDegrees: Float = 0, pitch: Float = FigureProportions.flatFootPitch) -> V3 {
        let yaw = side * toeOutDegrees * .pi / 180
        return V3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
    }

    /// Foot direction from a horizontal heading with the toe kept on or above the floor for the given ankle height.
    static func groundedFootDir(heading: V3, ankleY: Float, desiredPitch: Float) -> V3 {
        let maxPitch = asin(min(1, max(0, ankleY / FigureProportions.foot)))
        let p = min(desiredPitch, maxPitch)
        let h = safeNormalize(V3(heading.x, 0, heading.z), fallback: V3(0, 0, 1))
        return V3(h.x * cos(p), -sin(p), h.z * cos(p))
    }

    static func flatLeg(side: Float, x: Float = 0.13, z: Float = 0, toeOut: Float = 10, y: Float = FigureProportions.ankleHeight,
                        pole: V3? = nil) -> LegSpec {
        let dir = footDir(side: side, toeOutDegrees: toeOut)
        return .plant(ankle: V3(side * x, y, z), pole: pole ?? V3(side * 0.25 + dir.x, 0, 1), footDir: dir)
    }

    // MARK: Two-bone IK

    /// Returns the middle joint (elbow / knee) and the end joint actually reached (clamped, never stretched).
    static func twoBone(root: V3, target: V3, a: Float, b: Float, pole: V3) -> (mid: V3, end: V3) {
        var d = target - root
        var len = simd_length(d)
        if len < 1e-5 { d = V3(0, -1, 0); len = 1e-5 }
        let dir = d / len
        let maxLen = a + b - 0.002
        let minLen = abs(a - b) + 0.01
        let l = min(max(len, minLen), maxLen)
        let end = root + dir * l
        let along = (a * a - b * b + l * l) / (2 * l)
        let h = sqrt(max(0, a * a - along * along))
        var p = pole - dir * simd_dot(pole, dir)
        if simd_length(p) < 1e-4 {
            let alt = abs(dir.y) < 0.9 ? V3(0, 1, 0) : V3(0, 0, 1)
            p = alt - dir * simd_dot(alt, dir)
        }
        let mid = root + dir * along + safeNormalize(p) * h
        return (mid, end)
    }

    // MARK: Solve

    static func solve(_ s: PoseSpec) -> FigurePose {
        typealias P = FigureProportions
        var joints: [GuideJoint: V3] = [:]

        let pr = qy(s.pelvisYaw) * qx(s.pelvisPitch) * qz(s.pelvisRoll)
        joints[.pelvis] = s.pelvis
        joints[.leftHip] = s.pelvis + pr.act(V3(P.hipHalfWidth, 0, 0))
        joints[.rightHip] = s.pelvis + pr.act(V3(-P.hipHalfWidth, 0, 0))

        let lowerRot = pr * qx(s.spineLower)
        let spineMid = s.pelvis + lowerRot.act(V3(0, P.spineLower, 0))
        let upperRot = lowerRot * qx(s.spineUpper) * qz(s.spineBend)
        let chest = spineMid + upperRot.act(V3(0, P.spineUpper, 0))
        let chestRot = upperRot * qy(s.spineTwist)
        joints[.spineMid] = spineMid
        joints[.chest] = chest

        let lift = V3(0, s.shoulderLift, 0)
        let leftShoulder = chest + chestRot.act(V3(P.shoulderHalfWidth, 0, 0)) + lift
        let rightShoulder = chest + chestRot.act(V3(-P.shoulderHalfWidth, 0, 0)) + lift
        joints[.leftShoulder] = leftShoulder
        joints[.rightShoulder] = rightShoulder

        let neckRot = chestRot * qx(s.headPitch * 0.5)
        let neck = chest + neckRot.act(V3(0, P.neck, 0))
        let headRot = chestRot * qx(s.headPitch)
        joints[.neck] = neck
        joints[.head] = neck + headRot.act(V3(0, P.head, 0))

        func solveArm(_ spec: ArmSpec, shoulder: V3, side: Float, elbow: GuideJoint, wrist: GuideJoint, hand: GuideJoint) {
            func fk(upper: V3, flex: Float, bend: V3) {
                var b = bend - upper * simd_dot(bend, upper)
                if simd_length(b) < 1e-4 {
                    let alt = abs(upper.z) < 0.9 ? V3(0, 0, 1) : V3(0, 1, 0)
                    b = alt - upper * simd_dot(alt, upper)
                }
                b = safeNormalize(b)
                let f = upper * cos(flex) + b * sin(flex)
                let e = shoulder + upper * P.upperArm
                joints[elbow] = e
                joints[wrist] = e + f * P.forearm
                joints[hand] = e + f * (P.forearm + P.hand)
            }
            switch spec {
            case let .reach(handTarget, pole, handDirOpt):
                let handDir = safeNormalize(handDirOpt ?? (handTarget - shoulder))
                let wristTarget = handTarget - handDir * P.hand
                let r = twoBone(root: shoulder, target: wristTarget, a: P.upperArm, b: P.forearm, pole: pole)
                joints[elbow] = r.mid
                joints[wrist] = r.end
                joints[hand] = r.end + handDir * P.hand
            case let .fk(upper, flex, bend):
                fk(upper: chestRot.act(safeNormalize(upper)), flex: flex, bend: chestRot.act(bend))
            case let .fkWorld(upper, flex, bend):
                fk(upper: safeNormalize(upper), flex: flex, bend: bend)
            }
        }
        solveArm(s.leftArm, shoulder: leftShoulder, side: 1, elbow: .leftElbow, wrist: .leftWrist, hand: .leftHand)
        solveArm(s.rightArm, shoulder: rightShoulder, side: -1, elbow: .rightElbow, wrist: .rightWrist, hand: .rightHand)

        func solveLeg(_ spec: LegSpec, hip: V3, knee: GuideJoint, ankle: GuideJoint, toe: GuideJoint) {
            switch spec {
            case let .plant(ankleTarget, pole, footDir):
                let r = twoBone(root: hip, target: ankleTarget, a: P.thigh, b: P.shin, pole: pole)
                joints[knee] = r.mid
                joints[ankle] = r.end
                joints[toe] = r.end + safeNormalize(footDir, fallback: V3(0, 0, 1)) * P.foot
            }
        }
        solveLeg(s.leftLeg, hip: joints[.leftHip] ?? .zero, knee: .leftKnee, ankle: .leftAnkle, toe: .leftToe)
        solveLeg(s.rightLeg, hip: joints[.rightHip] ?? .zero, knee: .rightKnee, ankle: .rightAnkle, toe: .rightToe)

        return FigurePose(joints: joints, pelvisRotation: pr, chestRotation: chestRot, headRotation: headRot,
                          leftGripAxis: safeNormalize(s.leftGrip, fallback: V3(1, 0, 0)),
                          rightGripAxis: safeNormalize(s.rightGrip, fallback: V3(1, 0, 0)))
    }
}
