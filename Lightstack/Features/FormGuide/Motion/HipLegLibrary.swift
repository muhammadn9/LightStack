import Foundation
import simd

/// Leg curl, hip thrust, glute bridge, Nordic curl and calf raises.
enum HipLegLibrary {

    static func all() -> [ExerciseGuideMotion] {
        [legCurl(), hipThrust(name: "Hip Thrust", id: "hip-thrust", bench: true),
         hipThrust(name: "Glute Bridge", id: "glute-bridge", bench: false),
         nordicCurl(), standingCalfRaise(), seatedCalfRaise()]
    }

    // MARK: Hamstrings

    static func legCurl() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.onBench = true
        traits.drivingJoint = .leftAnkle
        return motion("Leg Curl", id: "leg-curl", duration: 4,
                      phases: [(0, "Legs straight"), (0.5, "Heels to glutes")],
                      primary: [.hamstrings], secondary: [.calves, .glutes],
                      camera: .side, focus: 0.6,
                      setup: ["Lie face down with your knees just past the edge of the pad.",
                              "Set the roller just above your heels.",
                              "Hold the handles and keep your hips pressed into the pad."],
                      cues: ["Curl your heels towards your glutes.",
                             "Keep your hips flat on the pad.",
                             "Lower slowly until your legs are almost straight."],
                      mistakes: ["Lifting your hips off the pad.",
                                 "Swinging the weight up with momentum.",
                                 "Dropping the weight fast on the way down."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec()
            s.pelvis = V3(0, 0.55, 0)
            s.pelvisPitch = .pi / 2
            let kneeL = V3(0.09, 0.55, -0.43)
            let kappa = Ease.rad(Ease.lerp(4, 100, d))
            let sd = V3(0, sin(kappa), -cos(kappa))
            let foot = V3(0, cos(kappa), sin(kappa))
            let a = kneeL + sd * FigureProportions.shin
            s.leftLeg = .plant(ankle: a, pole: V3(0, -1, -0.3), footDir: foot)
            s.rightLeg = .plant(ankle: V3(-a.x, a.y, a.z), pole: V3(0, -1, -0.3), footDir: foot)
            s.leftArm = .reach(hand: V3(0.30, 0.50, 0.86), pole: V3(0.6, -0.2, 0), handDir: nil)
            s.rightArm = .reach(hand: V3(-0.30, 0.50, 0.86), pole: V3(-0.6, -0.2, 0), handDir: nil)
            var props = Props.flatBench(padTop: 0.45, zMin: -0.40, zMax: 1.00, width: 0.34)
            props.append(Props.rod(V3(-0.2, a.y + 0.06, a.z - 0.02), V3(0.2, a.y + 0.06, a.z - 0.02), 0.04, .pad))
            props.append(Props.rod(V3(0.24, 0.40, -0.45), V3(0.24, a.y + 0.06, a.z - 0.02), 0.025))
            props.append(Props.rod(V3(-0.24, 0.40, -0.45), V3(-0.24, a.y + 0.06, a.z - 0.02), 0.025))
            props.append(Props.box(V3(0, 0.30, -0.75), V3(0.40, 0.55, 0.25), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .weightStack))
            return makeFrame(s, props)
        }
    }

    static func nordicCurl() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .chest
        return motion("Nordic Hamstring Curl", id: "nordic-hamstring-curl", duration: 5.2,
                      phases: [(0, "Kneeling tall"), (0.5, "Lowered forward")],
                      primary: [.hamstrings], secondary: [.glutes, .calves, .lowerBack],
                      camera: .side, focus: 0.6,
                      setup: ["Kneel on a pad and anchor your heels under a bar or a partner's hold.",
                              "Cross your arms in front of your chest.",
                              "Keep your hips extended so your body is one straight line from knees to head."],
                      cues: ["Lean forward as slowly as you can, resisting with your hamstrings.",
                             "Keep your hips open and your back straight.",
                             "Catch yourself with your hands, then push back up."],
                      mistakes: ["Folding at the hips instead of staying straight.",
                                 "Dropping forward fast with no control.",
                                 "Letting your heels lift off the anchor."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.06)
            let phi = Ease.rad(Ease.lerp(0, 68, d))
            var s = PoseSpec()
            let knee = V3(0, 0.05, 0.0)
            s.pelvis = knee + V3(0, cos(phi), sin(phi)) * FigureProportions.thigh
            s.pelvisPitch = phi
            s.headPitch = -phi * 0.6
            let ankle = V3(0.09, 0.08, -0.42)
            let foot = FigureSolver.safeNormalize(V3(0, -0.35, -0.94))
            s.leftLeg = .plant(ankle: ankle, pole: V3(0, -1, 0.3), footDir: foot)
            s.rightLeg = .plant(ankle: V3(-ankle.x, ankle.y, ankle.z), pole: V3(0, -1, 0.3), footDir: foot)
            let base = FigureSolver.solve(s)
            let chest = base.position(.chest)
            let front = base.chestRotation.act(V3(0, 0, 1))
            let blend = Ease.ramp(d, from: 0.9, to: 1.0) * 0.0
            var chestFront = chest + front * 0.20 + V3(0.10, -0.20, 0.0)
            chestFront.y = max(chestFront.y, 0.05)
            let hand = Ease.lerp(chestFront, V3(0.22, 0.05, chest.z + 0.24), blend)
            let hd = FigureSolver.safeNormalize(Ease.lerp(V3(-1, 0, 0), V3(0, 0, 1), blend))
            s.leftArm = .reach(hand: hand, pole: V3(0.5, 0.2, -0.5), handDir: hd)
            s.rightArm = .reach(hand: mirrorX(hand), pole: V3(-0.5, 0.2, -0.5), handDir: mirrorX(hd))
            let props: [GuideProp] = [
                Props.floorMat(center: V3(0, 0.01, 0.2), size: SIMD2<Float>(0.8, 1.6)),
                Props.box(V3(0, 0.0 + 0.19, -0.42), V3(0.5, 0.06, 0.10), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .pad),
                Props.rod(V3(0.3, 0, -0.45), V3(0.3, 0.19, -0.42), 0.03),
                Props.rod(V3(-0.3, 0, -0.45), V3(-0.3, 0.19, -0.42), 0.03)
            ]
            return makeFrame(s, props)
        }
    }

    // MARK: Glutes

    /// Hip thrust with the upper back on a bench, or a floor glute bridge. d: 0 = hips down, 1 = hips up.
    static func hipThrust(name: String, id: String, bench: Bool) -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.onBench = bench
        traits.bilateralBar = bench
        traits.drivingJoint = .pelvis
        let chest = bench ? V3(0, 0.55, -0.72) : V3(0, 0.10, -0.62)
        let ankleZ: Float = bench ? 0.17 : 0.15
        return motion(name, id: id, duration: 4,
                      phases: [(0, bench ? "Hips low" : "Hips on floor"), (0.5, "Hips fully up")],
                      primary: [.glutes], secondary: [.hamstrings, .quads, .abs],
                      camera: .side, focus: bench ? 0.55 : 0.3,
                      setup: bench ? ["Sit with your upper back against a bench and roll the bar over your hips.",
                                      "Place your feet flat, about hip-width apart.",
                                      "Hold the bar steady with both hands."]
                                   : ["Lie on your back with knees bent and feet flat, hip-width apart.",
                                      "Rest your arms on the floor beside you.",
                                      "Brace your abs and tuck your ribs down."],
                      cues: ["Drive your hips up by squeezing your glutes hard.",
                             "Finish with your torso level and shins vertical.",
                             "Keep your chin tucked and ribs down, then lower with control."],
                      mistakes: ["Arching your lower back at the top.",
                                 "Pushing through your toes instead of your heels.",
                                 "Letting your knees fall inward."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.14)
            // Torso angle below horizontal at the pelvis end (negative = hips above shoulders).
            let phi = Ease.rad(bench ? Ease.lerp(33, 5, d) : Ease.lerp(-2, -40, d))
            var s = PoseSpec()
            s.pelvis = chest + V3(0, -0.5 * sin(phi), 0.5 * cos(phi))
            s.pelvisPitch = -(.pi / 2 - phi)
            s.headPitch = bench ? 0.1 : max(0, -phi)
            let dir = FigureSolver.footDir(side: 1, toeOutDegrees: 8)
            s.leftLeg = .plant(ankle: V3(0.15, 0.08, ankleZ), pole: V3(0.2, 1, 0.3), footDir: dir)
            s.rightLeg = .plant(ankle: V3(-0.15, 0.08, ankleZ), pole: V3(-0.2, 1, 0.3), footDir: V3(-dir.x, dir.y, dir.z))
            let base = FigureSolver.solve(s)
            var props: [GuideProp] = []
            if bench {
                let front = base.pelvisRotation.act(V3(0, 0, 1))
                let bar = s.pelvis + front * 0.13
                s.gripBar(center: bar, halfGrip: 0.30, handDir: nil, pole: V3(0.6, -0.3, 0.2))
                props.append(Props.barbell(bar))
                props.append(Props.box(bar - front * 0.01 + V3(0, 0.0, 0), V3(0.12, 0.05, 0.12), base.pelvisRotation, .pad))
                props.append(contentsOf: Props.flatBench(padTop: 0.45, zMin: -1.15, zMax: -0.60, width: 0.34))
            } else {
                let hand = V3(0.28, 0.03, chest.z + 0.40)
                s.leftArm = .reach(hand: hand, pole: V3(0.5, 0.5, -0.5), handDir: V3(0, 0, 1))
                s.rightArm = .reach(hand: mirrorX(hand), pole: V3(-0.5, 0.5, -0.5), handDir: V3(0, 0, 1))
                props.append(Props.floorMat(center: V3(0, 0.005, -0.1), size: SIMD2<Float>(0.9, 2.0)))
            }
            return makeFrame(s, props)
        }
    }

    // MARK: Calves

    static func standingCalfRaise() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.drivingJoint = .pelvis
        traits.minPath = 0.15
        return motion("Standing Calf Raise", id: "standing-calf-raise", duration: 3.6,
                      phases: [(0, "Heels low"), (0.5, "Up on toes")],
                      primary: [.calves], secondary: [],
                      camera: .side, focus: 0.7,
                      setup: ["Set the shoulder pads so your legs are nearly straight when standing.",
                              "Place the balls of your feet on the platform edge, heels free.",
                              "Stand tall with your core braced."],
                      cues: ["Rise as high as you can onto your toes.",
                             "Pause and squeeze your calves at the top.",
                             "Lower slowly into a deep heel stretch."],
                      mistakes: ["Bouncing out of the bottom.",
                                 "Bending your knees to help the lift.",
                                 "Cutting the range short at the top or bottom."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.14)
            let h = Ease.lerp(0.03, 0.165, d)
            let p = asin(h / FigureProportions.foot)
            var s = PoseSpec()
            let toeL = V3(0.12, 0.10, 0.14)
            let dirL = FigureSolver.footDir(side: 1, toeOutDegrees: 8, pitch: p)
            let ankleL = toeL - dirL * FigureProportions.foot
            let dirR = FigureSolver.footDir(side: -1, toeOutDegrees: 8, pitch: p)
            let ankleR = V3(-0.12, 0.10, 0.14) - dirR * FigureProportions.foot
            s.leftLeg = .plant(ankle: ankleL, pole: V3(0.1, 0, 1), footDir: dirL)
            s.rightLeg = .plant(ankle: ankleR, pole: V3(-0.1, 0, 1), footDir: dirR)
            s.pelvis = V3(0, ankleL.y + 0.838, 0.0)
            let base = FigureSolver.solve(s)
            let chest = base.position(.chest)
            s.leftArm = .reach(hand: V3(0.30, chest.y - 0.30, 0.10), pole: V3(0.5, -0.3, -1), handDir: nil)
            s.rightArm = .reach(hand: V3(-0.30, chest.y - 0.30, 0.10), pole: V3(-0.5, -0.3, -1), handDir: nil)
            var props: [GuideProp] = [
                Props.box(V3(0, 0.05, 0.0), V3(0.60, 0.10, 0.50), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .platform),
                Props.box(V3(0, chest.y + 0.09, chest.z - 0.01), V3(0.50, 0.10, 0.30), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .pad),
                Props.rod(V3(0.30, 0.10, -0.40), V3(0.30, 2.0, -0.40), 0.04),
                Props.rod(V3(-0.30, 0.10, -0.40), V3(-0.30, 2.0, -0.40), 0.04),
                Props.rod(V3(0.30, chest.y + 0.14, -0.40), V3(0.28, chest.y + 0.14, chest.z), 0.03),
                Props.rod(V3(-0.30, chest.y + 0.14, -0.40), V3(-0.28, chest.y + 0.14, chest.z), 0.03)
            ]
            props.append(Props.box(V3(0, 0.50, -0.60), V3(0.40, 0.90, 0.25), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .weightStack))
            return makeFrame(s, props)
        }
    }

    static func seatedCalfRaise() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.onBench = true
        traits.drivingJoint = .leftKnee
        traits.minPath = 0.10
        let rig = Rigs.seated(seatTop: 0.50, backLean: 0, ankleZ: 0.45, withBackPad: false)
        return motion("Seated Calf Raise", id: "seated-calf-raise", duration: 3.6,
                      phases: [(0, "Heels low"), (0.5, "Up on toes")],
                      primary: [.calves], secondary: [],
                      camera: .side, focus: 0.6,
                      setup: ["Sit with the balls of your feet on the platform and the pad on your thighs.",
                              "Set your knees at about 90 degrees.",
                              "Release the safety and let your heels drop."],
                      cues: ["Push through the balls of your feet to rise high.",
                             "Squeeze your calves hard at the top.",
                             "Lower slowly into a full stretch."],
                      mistakes: ["Bouncing the weight at the bottom.",
                                 "Lifting only part of the way up.",
                                 "Rolling your ankles outward."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.14)
            let h = Ease.lerp(0.03, 0.165, d)
            let p = asin(h / FigureProportions.foot)
            var s = rig.spec
            let toeY: Float = 0.10
            let dirL = FigureSolver.footDir(side: 1, toeOutDegrees: 8, pitch: p)
            let dirR = FigureSolver.footDir(side: -1, toeOutDegrees: 8, pitch: p)
            let toeL = V3(0.14, toeY, 0.62)
            let ankleL = toeL - dirL * FigureProportions.foot
            let ankleR = V3(-0.14, toeY, 0.62) - dirR * FigureProportions.foot
            s.leftLeg = .plant(ankle: ankleL, pole: V3(0.1, 1, 0.2), footDir: dirL)
            s.rightLeg = .plant(ankle: ankleR, pole: V3(-0.1, 1, 0.2), footDir: dirR)
            let base = FigureSolver.solve(s)
            let kneeL = base.position(.leftKnee)
            s.leftArm = .reach(hand: kneeL + V3(0.0, 0.14, 0.0), pole: V3(0.4, 0, -1), handDir: nil)
            s.rightArm = .reach(hand: mirrorX(kneeL + V3(0.0, 0.14, 0.0)), pole: V3(-0.4, 0, -1), handDir: nil)
            var props = rig.props
            props.append(Props.box(V3(0, toeY - 0.06, 0.62), V3(0.60, 0.12, 0.40), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .platform))
            let padY = (kneeL.y + base.position(.rightKnee).y) / 2 + 0.09
            props.append(Props.box(V3(0, padY, kneeL.z - 0.04), V3(0.40, 0.10, 0.18), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .pad))
            props.append(Props.rod(V3(0.18, padY, kneeL.z - 0.04), V3(0.18, padY + 0.5, kneeL.z - 0.04), 0.03))
            props.append(Props.rod(V3(-0.18, padY, kneeL.z - 0.04), V3(-0.18, padY + 0.5, kneeL.z - 0.04), 0.03))
            props.append(Props.box(V3(0, 0.40, 1.00), V3(0.40, 0.7, 0.25), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .weightStack))
            return makeFrame(s, props)
        }
    }
}
