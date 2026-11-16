import Foundation
import simd

/// Abs and trunk work: plank, hanging leg raise, cable crunch, ab wheel, Russian twist, woodchopper.
enum CoreLibrary {

    static func all() -> [ExerciseGuideMotion] {
        [plank(), hangingLegRaise(), cableCrunch(), abWheelRollout(), russianTwist(), woodchopper()]
    }

    private static let identity = simd_quatf(angle: 0, axis: V3(0, 1, 0))

    static func plank() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.isometric = true
        traits.drivingJoint = .chest
        return motion("Plank", id: "plank", duration: 4,
                      phases: [(0, "Hold"), (0.5, "Breathe")],
                      primary: [.abs], secondary: [.obliques, .lowerBack, .glutes, .frontDelts],
                      camera: .side, focus: 0.4,
                      setup: ["Place your forearms on the floor with elbows directly under your shoulders.",
                              "Step your feet back so your body forms one straight line.",
                              "Brace your abs and squeeze your glutes."],
                      cues: ["Keep one straight line from your head to your heels.",
                             "Press your forearms into the floor and push the floor away.",
                             "Breathe steadily and keep your hips level."],
                      mistakes: ["Letting your hips sag towards the floor.",
                                 "Piking your hips up towards the ceiling.",
                                 "Holding your breath."],
                      traits: traits) { t in
            let breath = sin(2 * .pi * t)
            let ay: Float = 0.17
            let alpha = asin((0.35 - ay) / 1.35)
            let az = 0.05 - 1.35 * cos(alpha)
            let body = V3(0, sin(alpha), cos(alpha))
            var s = PoseSpec()
            s.pelvis = V3(0, ay, az) + body * 0.85
            s.pelvisPitch = .pi / 2 - alpha
            s.spineUpper = 0.02 * breath
            let p = asin(ay / FigureProportions.foot)
            let foot = V3(0, -sin(p), -cos(p))
            s.leftLeg = .plant(ankle: V3(0.10, ay, az), pole: V3(0, -1, 0), footDir: foot)
            s.rightLeg = .plant(ankle: V3(-0.10, ay, az), pole: V3(0, -1, 0), footDir: foot)
            s.armsFKWorld(upper: V3(0, -1, 0), flex: .pi / 2, bend: V3(0, 0, 1))
            s.leftGrip = V3(0, 0, 1)
            s.rightGrip = V3(0, 0, 1)
            return makeFrame(s, [Props.floorMat(center: V3(0, 0.005, -0.5), size: SIMD2<Float>(0.9, 2.2))])
        }
    }

    static func hangingLegRaise() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.drivingJoint = .leftAnkle
        let barY: Float = 2.30
        return motion("Hanging Leg Raise", id: "hanging-leg-raise", duration: 4.4,
                      phases: [(0, "Dead hang"), (0.5, "Legs level with hips")],
                      primary: [.abs, .hipFlexors], secondary: [.forearms, .obliques],
                      camera: .side, focus: 1.3,
                      setup: ["Grip a pull-up bar slightly wider than your shoulders and hang with straight arms.",
                              "Pull your shoulders down and keep your body still.",
                              "Squeeze your legs together."],
                      cues: ["Tilt your pelvis up and raise your legs together.",
                             "Lift until your legs are at least level with your hips.",
                             "Lower slowly without swinging."],
                      mistakes: ["Swinging your body to throw your legs up.",
                                 "Letting your shoulders shrug up to your ears.",
                                 "Dropping your legs fast on the way down."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec()
            let chest = V3(0, 1.68, -0.03)
            let lean = Ease.rad(-6 - 6 * d)
            s.pelvisPitch = lean
            s.pelvis = chest - V3(0, cos(lean), sin(lean)) * 0.5
            s.headPitch = 0.1
            s.gripBar(center: V3(0, barY, 0), halfGrip: 0.22, handDir: V3(0, 1, 0.2), pole: V3(0.7, -0.5, -0.3))
            let ang = Ease.rad(Ease.lerp(5, 98, d))
            let dir = V3(0, -cos(ang), sin(ang))
            let hipL = V3(0.09, s.pelvis.y, s.pelvis.z)
            let hipR = V3(-0.09, s.pelvis.y, s.pelvis.z)
            let foot = FigureSolver.safeNormalize(simd_cross(dir, V3(1, 0, 0)) + dir * 0.15)
            s.leftLeg = .plant(ankle: hipL + dir * 0.80, pole: V3(0, 1, 1), footDir: foot)
            s.rightLeg = .plant(ankle: hipR + dir * 0.80, pole: V3(0, 1, 1), footDir: foot)
            var props: [GuideProp] = [Props.rod(V3(-0.65, barY, 0), V3(0.65, barY, 0), 0.02, .frame)]
            props.append(Props.rod(V3(0.65, 0, 0), V3(0.65, barY, 0), 0.04))
            props.append(Props.rod(V3(-0.65, 0, 0), V3(-0.65, barY, 0), 0.04))
            props.append(Props.rod(V3(0.65, 0.02, -0.5), V3(0.65, 0.02, 0.5), 0.03))
            props.append(Props.rod(V3(-0.65, 0.02, -0.5), V3(-0.65, 0.02, 0.5), 0.03))
            return makeFrame(s, props)
        }
    }

    static func cableCrunch() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .head
        return motion("Cable Crunch", id: "cable-crunch", duration: 3.8,
                      phases: [(0, "Kneeling tall"), (0.5, "Crunched down")],
                      primary: [.abs], secondary: [.obliques, .hipFlexors],
                      camera: .side, focus: 0.8,
                      setup: ["Set the pulley high and attach a rope.",
                              "Kneel facing the stack and hold the rope beside your head.",
                              "Keep your hips still and your knees under your hips."],
                      cues: ["Curl your ribs down towards your pelvis.",
                             "Bring your elbows towards your knees.",
                             "Return slowly to the tall position."],
                      mistakes: ["Pulling the weight down with your arms and hips.",
                                 "Sitting back onto your heels as you crunch.",
                                 "Using a weight so heavy you lose the curl."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.12)
            var s = PoseSpec()
            s.pelvis = V3(0, 0.48, 0)
            s.spineLower = 0.42 * d
            s.spineUpper = 0.50 * d
            s.headPitch = 0.30 * d
            let ankle = V3(0.12, 0.08, -0.42)
            let foot = FigureSolver.safeNormalize(V3(0, -0.35, -0.94))
            s.leftLeg = .plant(ankle: ankle, pole: V3(0, -0.7, 0.7), footDir: foot)
            s.rightLeg = .plant(ankle: V3(-ankle.x, ankle.y, ankle.z), pole: V3(0, -0.7, 0.7), footDir: foot)
            let base = FigureSolver.solve(s)
            let rot = base.chestRotation
            let chest = base.position(.chest)
            let up = rot.act(V3(0, 1, 0))
            let l = chest + rot.act(V3(0.14, 0.05, 0.20))
            s.leftArm = .reach(hand: l, pole: rot.act(V3(0.3, -1, 0.2)), handDir: up)
            s.rightArm = .reach(hand: chest + rot.act(V3(-0.14, 0.05, 0.20)), pole: rot.act(V3(-0.3, -1, 0.2)), handDir: up)
            let mid = chest + rot.act(V3(0, 0.05, 0.20))
            var props: [GuideProp] = [
                .handle(center: mid, axis: V3(1, 0, 0), length: 0.30),
                .cable(from: V3(0, 2.10, 0.55), to: mid),
                Props.floorMat(center: V3(0, 0.01, -0.1), size: SIMD2<Float>(0.9, 1.4))
            ]
            props.append(contentsOf: Props.tower(x: 0, z: 0.60, pulleyY: 2.10))
            return makeFrame(s, props)
        }
    }

    static func abWheelRollout() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .chest
        return motion("Ab Wheel Rollout", id: "ab-wheel-rollout", duration: 5,
                      phases: [(0, "Kneeling, hips flexed"), (0.5, "Fully rolled out")],
                      primary: [.abs], secondary: [.lats, .lowerBack, .frontDelts, .hipFlexors],
                      camera: .side, focus: 0.5,
                      setup: ["Kneel on a mat holding the wheel handles directly below your shoulders.",
                              "Tuck your pelvis under and round your upper back slightly.",
                              "Brace your abs hard before you roll."],
                      cues: ["Roll the wheel forward slowly, keeping your hips tucked.",
                             "Stop before your lower back starts to sag.",
                             "Pull the wheel back by drawing your ribs to your hips."],
                      mistakes: ["Letting your lower back arch and sag.",
                                 "Rolling out further than you can pull back from.",
                                 "Bending at the hips instead of rolling with your abs."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.08)
            let phi = Ease.rad(Ease.lerp(0, 68, d))
            let theta = Ease.rad(Ease.lerp(66, 80, d))
            var s = PoseSpec()
            let knee = V3(0, 0.05, 0.0)
            s.pelvis = knee + V3(0, cos(phi), sin(phi)) * FigureProportions.thigh
            s.pelvisPitch = theta
            s.headPitch = -0.5 * theta
            let ankle = V3(0.09, 0.08, -0.42)
            let foot = FigureSolver.safeNormalize(V3(0, -0.35, -0.94))
            s.leftLeg = .plant(ankle: ankle, pole: V3(0, -1, 0.3), footDir: foot)
            s.rightLeg = .plant(ankle: V3(-ankle.x, ankle.y, ankle.z), pole: V3(0, -1, 0.3), footDir: foot)
            let base = FigureSolver.solve(s)
            let chest = base.position(.chest)
            let wz = chest.z + Ease.lerp(0.12, 0.40, d)
            let hand = V3(0.12, 0.10, wz)
            let hd = FigureSolver.safeNormalize(V3(0, -1, 0.3))
            s.leftArm = .reach(hand: hand, pole: V3(0.3, 0.3, -1), handDir: hd)
            s.rightArm = .reach(hand: mirrorX(hand), pole: V3(-0.3, 0.3, -1), handDir: mirrorX(hd))
            s.leftGrip = V3(1, 0, 0)
            s.rightGrip = V3(1, 0, 0)
            let props: [GuideProp] = [
                Props.floorMat(center: V3(0, 0.01, 0.4), size: SIMD2<Float>(0.9, 2.2)),
                .cylinder(from: V3(-0.07, 0.10, wz), to: V3(0.07, 0.10, wz), radius: 0.10, kind: .platform),
                .handle(center: V3(0, 0.10, wz), axis: V3(1, 0, 0), length: 0.34)
            ]
            return makeFrame(s, props)
        }
    }

    static func russianTwist() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Russian Twist", id: "russian-twist", duration: 4.4,
                      phases: [(0, "Centre"), (0.25, "Twist left"), (0.5, "Centre"), (0.75, "Twist right")],
                      primary: [.obliques], secondary: [.abs, .hipFlexors],
                      camera: .front, focus: 0.5,
                      setup: ["Sit on the floor with your knees bent and feet flat.",
                              "Lean back until your torso is about 45 degrees from the floor.",
                              "Clasp your hands together in front of your chest."],
                      cues: ["Rotate your whole torso from side to side.",
                             "Keep your chest tall and your back straight.",
                             "Move your hands with your ribs, not just your arms."],
                      mistakes: ["Swinging only your arms side to side.",
                                 "Rounding your back as you lean.",
                                 "Rushing so you lose control of the twist."],
                      traits: traits) { t in
            var s = PoseSpec()
            s.pelvis = V3(0, 0.13, 0)
            s.pelvisPitch = -Ease.rad(35)
            s.spineTwist = Ease.rad(55) * sin(2 * .pi * t)
            let dir = FigureSolver.footDir(side: 1, toeOutDegrees: 8)
            s.leftLeg = .plant(ankle: V3(0.12, 0.08, 0.55), pole: V3(0.1, 1, 0.3), footDir: dir)
            s.rightLeg = .plant(ankle: V3(-0.12, 0.08, 0.55), pole: V3(-0.1, 1, 0.3), footDir: V3(-dir.x, dir.y, dir.z))
            let base = FigureSolver.solve(s)
            let rot = base.chestRotation
            let chest = base.position(.chest)
            let center = chest + rot.act(V3(0, -0.12, 0.34))
            let fwd = rot.act(V3(0, 0, 1))
            s.leftArm = .reach(hand: center + rot.act(V3(0.05, 0, 0)), pole: rot.act(V3(0.5, -1, 0.1)), handDir: fwd)
            s.rightArm = .reach(hand: center + rot.act(V3(-0.05, 0, 0)), pole: rot.act(V3(-0.5, -1, 0.1)), handDir: fwd)
            return makeFrame(s, [Props.floorMat(center: V3(0, 0.005, 0.2), size: SIMD2<Float>(0.9, 1.8))])
        }
    }

    static func woodchopper() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Woodchopper", id: "woodchopper", duration: 4,
                      phases: [(0, "High at left"), (0.5, "Low at right")],
                      primary: [.obliques], secondary: [.abs, .frontDelts, .glutes],
                      camera: .front, focus: 1.0,
                      setup: ["Set the cable pulley high and stand side-on to the stack.",
                              "Plant your feet wider than your shoulders with knees soft.",
                              "Hold the handle with both hands, arms nearly straight."],
                      cues: ["Chop diagonally down across your body from high to low.",
                             "Rotate through your hips and torso, not just your arms.",
                             "Control the handle back up to the start."],
                      mistakes: ["Bending your elbows and pulling with your arms.",
                                 "Keeping your hips locked so your lower back twists.",
                                 "Using a weight that makes you jerk."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.06)
            var s = PoseSpec.standing(stance: 0.25, toeOut: 20, pelvisY: 0.90)
            let total = Ease.rad(Ease.lerp(45, -45, d))
            s.pelvisYaw = 0.3 * total
            s.spineTwist = 0.7 * total
            s.spineLower = 0.2 * d
            s.headPitch = 0.1 * d
            let base = FigureSolver.solve(s)
            let rot = base.chestRotation
            let chest = base.position(.chest)
            let ly = Ease.lerp(0.30, -0.40, d)
            let leftHand = chest + rot.act(V3(0.05, ly, 0.34))
            let rightHand = chest + rot.act(V3(-0.05, ly, 0.34))
            let fwd = rot.act(V3(0, 0, 1))
            s.leftArm = .reach(hand: leftHand, pole: rot.act(V3(0.5, -0.5, 0)), handDir: fwd)
            s.rightArm = .reach(hand: rightHand, pole: rot.act(V3(-0.5, -0.5, 0)), handDir: fwd)
            s.leftGrip = fwd
            s.rightGrip = fwd
            let mid = (leftHand + rightHand) / 2
            var props: [GuideProp] = [
                .handle(center: mid, axis: rot.act(V3(1, 0, 0)), length: 0.28),
                .cable(from: V3(1.0, 2.10, 0.1), to: mid)
            ]
            props.append(contentsOf: Props.tower(x: 1.0, z: 0.1, pulleyY: 2.10))
            return makeFrame(s, props)
        }
    }
}
