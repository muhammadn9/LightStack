import Foundation
import simd

/// Squats, leg press, hack squat, leg extension and lunge variations.
enum SquatLibrary {

    static func all() -> [ExerciseGuideMotion] {
        [barbellSquat(), frontSquat(), gobletSquat(), hackSquat(), legPress(), legExtension(), bulgarianSplitSquat(), walkingLunge()]
    }

    /// Forward lean (radians) that puts a point at chest-local offset (oy, oz) over `targetZ`.
    static func solveLean(pelvisZ: Float, oy: Float, oz: Float, targetZ: Float) -> Float {
        func z(_ th: Float) -> Float { pelvisZ + (0.5 + oy) * sin(th) + oz * cos(th) }
        if z(0) >= targetZ { return 0 }
        var lo: Float = 0, hi: Float = 1.3
        for _ in 0..<30 {
            let mid = (lo + hi) / 2
            if z(mid) < targetZ { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    private enum BarKind { case back, front, goblet }

    private static func squatBase(kind: BarKind, name: String, id: String, stance: Float, toeOut: Float,
                                  bottomY: Float, bottomZ: Float, template: MotionTraits.Template,
                                  primary: [MuscleGroup], secondary: [MuscleGroup],
                                  setup: [String], cues: [String], mistakes: [String]) -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.template = template
        traits.feetPlanted = true
        traits.bilateralBar = kind != .goblet
        traits.drivingJoint = .pelvis
        return motion(name, id: id, duration: 4.4,
                      phases: [(0, "Standing"), (0.5, "Bottom of squat")],
                      primary: primary, secondary: secondary, camera: .side, focus: 0.9,
                      setup: setup, cues: cues, mistakes: mistakes, traits: traits) { t in
            let d = Ease.profile(t, hold: 0.08)
            var s = PoseSpec.standing(stance: stance, toeOut: toeOut)
            s.pelvis = V3(0, Ease.lerp(0.925, bottomY, d), Ease.lerp(0.0, bottomZ, d))
            let oy: Float, oz: Float
            let targetZ: Float
            switch kind {
            case .back: oy = 0.05; oz = -0.10; targetZ = Ease.lerp(-0.08, 0.06, d)
            case .front: oy = 0.03; oz = 0.12; targetZ = Ease.lerp(0.12, 0.06, d)
            case .goblet: oy = 0; oz = 0.17; targetZ = Ease.lerp(0.17, 0.12, d)
            }
            let lean = solveLean(pelvisZ: s.pelvis.z, oy: oy, oz: oz, targetZ: targetZ)
            s.pelvisPitch = lean
            s.headPitch = -lean * 0.55
            switch kind {
            case .back:
                let bar = Rigs.holdBackBar(&s)
                return makeFrame(s, [Props.barbell(bar)] + Props.rack(z: -0.55, height: 1.50))
            case .front:
                let base = FigureSolver.solve(s)
                let rot = base.chestRotation
                let bar = base.position(.chest) + rot.act(V3(0, 0.03, 0.12))
                s.gripBar(center: bar, halfGrip: 0.15, handDir: rot.act(FigureSolver.safeNormalize(V3(0, 0.5, -0.85))),
                          pole: rot.act(V3(0.1, 0.6, 1)))
                return makeFrame(s, [Props.barbell(bar)] + Props.rack(z: -0.55, height: 1.50))
            case .goblet:
                let base = FigureSolver.solve(s)
                let rot = base.chestRotation
                let chest = base.position(.chest)
                let center = chest + rot.act(V3(0, -0.02, 0.17))
                let up = rot.act(V3(0, 1, 0))
                s.leftArm = .reach(hand: center + rot.act(V3(0.06, 0.07, 0)), pole: rot.act(V3(0.5, -1, 0.3)), handDir: up)
                s.rightArm = .reach(hand: center + rot.act(V3(-0.06, 0.07, 0)), pole: rot.act(V3(-0.5, -1, 0.3)), handDir: up)
                s.leftGrip = up
                s.rightGrip = up
                return makeFrame(s, [.dumbbell(center: center, axis: up)])
            }
        }
    }

    static func barbellSquat() -> ExerciseGuideMotion {
        squatBase(kind: .back, name: "Barbell Squat", id: "barbell-squat", stance: 0.20, toeOut: 18,
                  bottomY: 0.41, bottomZ: -0.20, template: .squat,
                  primary: [.quads, .glutes], secondary: [.hamstrings, .adductors, .lowerBack, .abs],
                  setup: ["Set the bar across your upper back and grip it just outside your shoulders.",
                          "Step back with feet shoulder-width apart and toes turned slightly out.",
                          "Take a big breath and brace your abs before you descend."],
                  cues: ["Sit your hips back and down while your knees track over your toes.",
                         "Keep your chest up and the bar over your mid-foot.",
                         "Drive through your whole foot to stand, hips and shoulders rising together."],
                  mistakes: ["Letting your knees cave inward.",
                             "Lifting your heels off the floor.",
                             "Rounding your lower back at the bottom."])
    }

    static func frontSquat() -> ExerciseGuideMotion {
        squatBase(kind: .front, name: "Front Squat", id: "front-squat", stance: 0.20, toeOut: 15,
                  bottomY: 0.42, bottomZ: -0.18, template: .squat,
                  primary: [.quads], secondary: [.glutes, .abs, .upperBack],
                  setup: ["Rest the bar on your front delts and keep your elbows high.",
                          "Step back with feet shoulder-width apart and toes slightly out.",
                          "Brace your abs and keep your chest tall."],
                  cues: ["Squat straight down, keeping your elbows pointing forward.",
                         "Keep your torso as upright as possible.",
                         "Drive up through your whole foot while keeping the bar still."],
                  mistakes: ["Letting your elbows drop and the bar roll forward.",
                             "Leaning forward as you rise.",
                             "Letting your knees collapse inward."])
    }

    static func gobletSquat() -> ExerciseGuideMotion {
        squatBase(kind: .goblet, name: "Goblet Squat", id: "goblet-squat", stance: 0.21, toeOut: 20,
                  bottomY: 0.44, bottomZ: -0.20, template: .other,
                  primary: [.quads, .glutes], secondary: [.abs, .adductors, .upperBack],
                  setup: ["Hold one dumbbell vertically against your chest with both hands.",
                          "Stand with feet slightly wider than shoulder-width, toes turned out.",
                          "Keep your elbows pointing down and your chest tall."],
                  cues: ["Sit straight down between your knees.",
                         "Keep your elbows inside your knees at the bottom.",
                         "Push the floor away to stand tall."],
                  mistakes: ["Letting the dumbbell drift away from your chest.",
                             "Rounding forward at the bottom.",
                             "Lifting your heels off the floor."])
    }

    // MARK: Machines

    static func hackSquat() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.onBench = true
        traits.drivingJoint = .pelvis
        let slope = V3(0, -0.866, 0.5)
        let top = V3(0, 0.86, -0.25)
        return motion("Hack Squat", id: "hack-squat", duration: 4.4,
                      phases: [(0, "Legs extended"), (0.5, "Deep squat")],
                      primary: [.quads], secondary: [.glutes, .adductors, .hamstrings],
                      camera: .side, focus: 0.7,
                      setup: ["Stand on the platform with feet shoulder-width apart, shoulders under the pads.",
                              "Press your back flat into the pad and release the safety handles.",
                              "Place your feet far enough forward to keep your heels down."],
                      cues: ["Lower until your thighs are at least parallel to the platform.",
                             "Keep your whole back against the pad.",
                             "Push through your whole foot and stop just short of locking out."],
                      mistakes: ["Letting your heels rise off the platform.",
                                 "Letting your knees cave inward.",
                                 "Bouncing out of the bottom."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.08)
            var s = PoseSpec()
            s.pelvis = top + slope * (0.42 * d)
            s.pelvisPitch = -Ease.rad(30)
            s.headPitch = 0.3
            let dir = FigureSolver.footDir(side: 1, toeOutDegrees: 14)
            s.leftLeg = .plant(ankle: V3(0.20, 0.14, 0.15), pole: V3(0.3, 0.2, 1), footDir: dir)
            s.rightLeg = .plant(ankle: V3(-0.20, 0.14, 0.15), pole: V3(-0.3, 0.2, 1), footDir: V3(-dir.x, dir.y, dir.z))
            let base = FigureSolver.solve(s)
            let rot = base.chestRotation
            let chest = base.position(.chest)
            let hand = chest + rot.act(V3(0.30, -0.20, 0.22))
            s.leftArm = .reach(hand: hand, pole: V3(0.5, -1, -0.2), handDir: V3(0, 0, 1))
            s.rightArm = .reach(hand: V3(-hand.x, hand.y, hand.z), pole: V3(-0.5, -1, -0.2), handDir: V3(0, 0, 1))
            let up = base.pelvisRotation.act(V3(0, 1, 0))
            let front = base.pelvisRotation.act(V3(0, 0, 1))
            let padCenter = s.pelvis + up * 0.24 - front * 0.14
            var props: [GuideProp] = [
                Props.box(padCenter, V3(0.40, 0.78, 0.08), base.pelvisRotation),
                Props.box(chest + rot.act(V3(0.27, 0.0, -0.03)), V3(0.12, 0.08, 0.16), rot, .pad),
                Props.box(chest + rot.act(V3(-0.27, 0.0, -0.03)), V3(0.12, 0.08, 0.16), rot, .pad),
                Props.box(V3(0, 0.03, 0.15), V3(0.80, 0.06, 0.55), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .platform),
                Props.rod(V3(0.38, 0.0, -0.75), V3(0.38, 1.9, -1.2), 0.035),
                Props.rod(V3(-0.38, 0.0, -0.75), V3(-0.38, 1.9, -1.2), 0.035),
                Props.rod(V3(0.38, 0.0, -0.75), V3(0.38, 0.0, 0.5), 0.03),
                Props.rod(V3(-0.38, 0.0, -0.75), V3(-0.38, 0.0, 0.5), 0.03)
            ]
            props.append(Props.rod(chest + rot.act(V3(0.30, -0.20, 0.22)), chest + rot.act(V3(0.30, -0.20, 0.0)), 0.025))
            props.append(Props.rod(chest + rot.act(V3(-0.30, -0.20, 0.22)), chest + rot.act(V3(-0.30, -0.20, 0.0)), 0.025))
            return makeFrame(s, props)
        }
    }

    static func legPress() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.onBench = true
        traits.drivingJoint = .leftAnkle
        let u = V3(0, 0.707, 0.707)
        let w = V3(0, 0.707, -0.707)
        let pelvis = V3(0, 0.40, -0.30)
        let legDir = FigureSolver.safeNormalize(V3(0, 0.60, 0.80))
        let ankleTop = pelvis + legDir * 0.82
        let pitch = FigureProportions.flatFootPitch
        let toeDir = w * cos(pitch) + u * sin(pitch)
        return motion("Leg Press", id: "leg-press", duration: 4.4,
                      phases: [(0, "Legs extended"), (0.5, "Knees bent")],
                      primary: [.quads, .glutes], secondary: [.hamstrings, .adductors, .calves],
                      camera: .side, focus: 0.65,
                      setup: ["Sit with your back and hips flat against the pad.",
                              "Place your feet shoulder-width apart in the middle of the platform.",
                              "Release the safety handles and hold the side grips."],
                      cues: ["Lower the platform until your knees reach about 90 degrees.",
                             "Keep your hips and lower back pressed into the pad.",
                             "Press through your heels without locking your knees."],
                      mistakes: ["Letting your hips curl off the seat at the bottom.",
                                 "Locking your knees hard at the top.",
                                 "Letting your knees fall inward."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.08)
            var s = PoseSpec()
            s.pelvis = pelvis
            s.pelvisPitch = -Ease.rad(50)
            let a = ankleTop - u * (0.45 * d)
            s.leftLeg = .plant(ankle: a + V3(0.20, 0, 0), pole: V3(0.25, 0.7, -0.7), footDir: toeDir)
            s.rightLeg = .plant(ankle: a + V3(-0.20, 0, 0), pole: V3(-0.25, 0.7, -0.7), footDir: V3(-toeDir.x, toeDir.y, toeDir.z))
            s.leftArm = .reach(hand: pelvis + V3(0.30, 0.12, 0.12), pole: V3(0.5, 0, -1), handDir: nil)
            s.rightArm = .reach(hand: pelvis + V3(-0.30, 0.12, 0.12), pole: V3(-0.5, 0, -1), handDir: nil)
            let base = FigureSolver.solve(s)
            var props = Props.backSupport(pelvis: pelvis, pelvisRot: base.pelvisRotation, length: 0.95, width: 0.40)
            let plateCenter = V3(0, a.y, a.z) + u * 0.10 + w * 0.08
            props.append(Props.box(plateCenter, V3(0.74, 0.80, 0.04), Props.orient(y: w, zHint: u), .platform))
            props.append(Props.rod(V3(0.38, 0.02, -0.55) , V3(0.38, plateCenter.y + 0.2, plateCenter.z + 0.2), 0.018))
            props.append(Props.rod(V3(-0.38, 0.02, -0.55), V3(-0.38, plateCenter.y + 0.2, plateCenter.z + 0.2), 0.018))
            props.append(Props.box(V3(0, 0.55, 0.95), V3(0.5, 0.5, 0.3), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .weightStack))
            return makeFrame(s, props)
        }
    }

    static func legExtension() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.onBench = true
        traits.drivingJoint = .leftAnkle
        let rig = Rigs.seated(seatTop: 0.45, backLean: 10, ankleZ: 0.42)
        let hip = V3(0.09, 0.55, 0)
        let kneeDir = FigureSolver.safeNormalize(V3(0, -0.06, 1))
        let knee = hip + kneeDir * FigureProportions.thigh
        return motion("Leg Extension", id: "leg-extension", duration: 4,
                      phases: [(0, "Knees bent"), (0.5, "Legs extended")],
                      primary: [.quads], secondary: [],
                      camera: .side, focus: 0.55,
                      setup: ["Adjust the back pad so your knees line up with the machine's pivot.",
                              "Sit tall and set the roller on your lower shins above your ankles.",
                              "Hold the side handles and keep your hips down."],
                      cues: ["Extend your legs until they are nearly straight.",
                             "Squeeze your quads for a second at the top.",
                             "Lower slowly for a count of three."],
                      mistakes: ["Swinging the weight up with momentum.",
                                 "Lifting your hips off the seat.",
                                 "Dropping the weight instead of lowering it."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.12)
            var s = rig.spec
            let phi = Ease.rad(Ease.lerp(85, 8, d))
            let sd = V3(0, -sin(phi), cos(phi))
            let foot = V3(0, cos(phi), sin(phi))
            let a = knee + sd * FigureProportions.shin
            s.leftLeg = .plant(ankle: a, pole: V3(0, 1, 0.2), footDir: foot)
            s.rightLeg = .plant(ankle: V3(-a.x, a.y, a.z), pole: V3(0, 1, 0.2), footDir: foot)
            s.leftArm = .reach(hand: V3(0.31, 0.64, 0.12), pole: V3(0.6, 0, -1), handDir: nil)
            s.rightArm = .reach(hand: V3(-0.31, 0.64, 0.12), pole: V3(-0.6, 0, -1), handDir: nil)
            var props = rig.props
            let roller = a + V3(0, 0.0, 0.0) + sd * 0.0 + foot * (-0.05) - V3(0, 0, 0)
            props.append(Props.rod(V3(-0.25, roller.y + 0.03, roller.z + 0.06), V3(0.25, roller.y + 0.03, roller.z + 0.06), 0.04, .pad))
            props.append(Props.rod(V3(0.28, knee.y - 0.06, knee.z - 0.02), V3(0.28, roller.y + 0.03, roller.z + 0.06), 0.025))
            props.append(Props.rod(V3(-0.28, knee.y - 0.06, knee.z - 0.02), V3(-0.28, roller.y + 0.03, roller.z + 0.06), 0.025))
            props.append(Props.box(V3(0, 0.45, -0.65), V3(0.40, 0.8, 0.25), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .weightStack))
            return makeFrame(s, props)
        }
    }

    // MARK: Lunges

    static func bulgarianSplitSquat() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.onBench = true
        traits.drivingJoint = .pelvis
        return motion("Bulgarian Split Squat", id: "bulgarian-split-squat", duration: 4.6,
                      phases: [(0, "Standing"), (0.5, "Bottom")],
                      primary: [.quads, .glutes], secondary: [.hamstrings, .adductors, .abs],
                      camera: .side, focus: 0.8,
                      setup: ["Stand facing away from a bench and rest one rear foot on it, laces down.",
                              "Step your front foot far enough out that your shin stays vertical at the bottom.",
                              "Hold a dumbbell in each hand at your sides."],
                      cues: ["Lower straight down until your front thigh is parallel to the floor.",
                             "Keep your torso tall and your front heel planted.",
                             "Drive through your front foot to stand."],
                      mistakes: ["Placing the front foot too close so your knee travels far forward.",
                                 "Letting your front knee cave inward.",
                                 "Leaning far forward over your front leg."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.08)
            var s = PoseSpec()
            s.pelvis = V3(0, Ease.lerp(0.83, 0.57, d), Ease.lerp(-0.10, -0.08, d))
            s.pelvisPitch = Ease.rad(10)
            s.headPitch = -0.15
            let front = FigureSolver.footDir(side: 1, toeOutDegrees: 6)
            s.leftLeg = .plant(ankle: V3(0.10, 0.08, 0.26), pole: V3(0.1, 0.3, 1), footDir: front)
            s.rightLeg = .plant(ankle: V3(-0.10, 0.54, -0.72), pole: V3(0, -1, 0), footDir: V3(0, -0.4, -0.917))
            s.armsFKWorld(upper: V3(0.0, -1, 0), flex: 0.05, bend: V3(0, 0, 1))
            s.leftGrip = V3(0, 0, 1)
            s.rightGrip = V3(0, 0, 1)
            let pose = FigureSolver.solve(s)
            var props = Props.flatBench(padTop: 0.45, zMin: -1.05, zMax: -0.55, width: 0.34)
            props.append(.dumbbell(center: pose.position(.leftHand), axis: V3(0, 0, 1)))
            props.append(.dumbbell(center: pose.position(.rightHand), axis: V3(0, 0, 1)))
            return GuideFrame(pose: pose, props: props)
        }
    }

    static func walkingLunge() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.drivingJoint = .pelvis
        traits.maxStep = 0.17   // the stepping foot travels about 0.8 m twice per rep
        return motion("Walking Lunge", id: "walking-lunge", duration: 6.4,
                      phases: [(0, "Standing"), (0.25, "Left lunge"), (0.5, "Standing"), (0.75, "Right lunge")],
                      primary: [.quads, .glutes], secondary: [.hamstrings, .adductors, .calves],
                      camera: .side, focus: 0.85,
                      setup: ["Stand tall holding a dumbbell in each hand at your sides.",
                              "Brace your abs and keep your chest up.",
                              "Take a long step forward, enough that your front shin stays upright."],
                      cues: ["Lower until both knees are bent to about 90 degrees.",
                             "Keep your torso upright and your front knee over your foot.",
                             "Push off your front foot and bring your feet together, then switch legs."],
                      mistakes: ["Taking steps too short so your knee runs far over your toes.",
                                 "Letting your front knee cave inward.",
                                 "Leaning your torso forward."],
                      traits: traits) { t in
            let leftTurn = t < 0.5
            let local = leftTurn ? t * 2 : (t - 0.5) * 2
            let u = Ease.profile(local, hold: 0.04)
            let u1 = Ease.clamp01(u / 0.85)
            let u2 = Ease.clamp01((u - 0.25) / 0.75)
            let stepZ: Float = 0.80
            let side: Float = leftTurn ? 1 : -1   // stepping leg side
            var s = PoseSpec.standing(stance: 0.12, toeOut: 6)
            s.pelvis = V3(0, Ease.lerp(0.90, 0.56, u2), Ease.lerp(0.0, 0.47, u2))
            s.headPitch = 0
            // Stepping foot.
            let stepAnkle = V3(side * 0.12, 0.08 + 0.13 * sin(.pi * u1), stepZ * u1)
            let stepDir = FigureSolver.groundedFootDir(heading: V3(side * 0.1, 0, 1), ankleY: stepAnkle.y,
                                                       desiredPitch: Ease.lerp(FigureProportions.flatFootPitch, 0.5, sin(.pi * u1) * 0.7))
            let stepLeg: LegSpec = .plant(ankle: stepAnkle, pole: Ease.lerp(V3(side * 0.1, 0, 1), V3(side * 0.1, 0.3, 1), u1), footDir: stepDir)
            // Rear foot: ball stays put while the heel lifts.
            let flatDir = FigureSolver.footDir(side: -side, toeOutDegrees: 6)
            let rearToe = V3(-side * 0.12, 0.08, 0) + flatDir * FigureProportions.foot
            let p = asin(min(0.95, (0.08 + 0.10 * u2) / FigureProportions.foot))
            let rearDir = FigureSolver.footDir(side: -side, toeOutDegrees: 6, pitch: p)
            let rearAnkle = rearToe - rearDir * FigureProportions.foot
            let rearLeg: LegSpec = .plant(ankle: rearAnkle, pole: Ease.lerp(V3(-side * 0.1, 0, 1), V3(-side * 0.1, -0.4, 1), u2), footDir: rearDir)
            if leftTurn { s.leftLeg = stepLeg; s.rightLeg = rearLeg } else { s.rightLeg = stepLeg; s.leftLeg = rearLeg }
            s.armsFKWorld(upper: V3(0.0, -1, 0), flex: 0.05, bend: V3(0, 0, 1))
            s.leftGrip = V3(0, 0, 1)
            s.rightGrip = V3(0, 0, 1)
            let pose = FigureSolver.solve(s)
            return GuideFrame(pose: pose, props: [.dumbbell(center: pose.position(.leftHand), axis: V3(0, 0, 1)),
                                                  .dumbbell(center: pose.position(.rightHand), axis: V3(0, 0, 1)),
                                                  Props.floorMat(center: V3(0, 0.005, 0.3), size: SIMD2<Float>(0.9, 2.2))])
        }
    }
}
