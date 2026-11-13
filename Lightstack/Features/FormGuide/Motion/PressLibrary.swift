import Foundation
import simd

/// Chest work, shoulder presses, dips and push-ups.
enum PressLibrary {

    static func all() -> [ExerciseGuideMotion] {
        var out: [ExerciseGuideMotion] = []
        out.append(lyingPress(name: "Barbell Bench Press", id: "barbell-bench-press", incline: 0, dumbbells: false,
                              halfGrip: 0.37, template: .benchPress,
                              muscles: ([.chest], [.frontDelts, .triceps]),
                              setup: ["Lie back so your eyes sit under the bar and plant your feet flat.",
                                      "Pull your shoulder blades together and keep a slight arch.",
                                      "Grip just wider than shoulder-width and unrack with straight arms."],
                              cues: ["Lower the bar to your lower chest with elbows at about 45 degrees.",
                                     "Keep your forearms vertical at the bottom.",
                                     "Press up and slightly back until your arms lock out."],
                              mistakes: ["Flaring your elbows out to 90 degrees.",
                                         "Bouncing the bar off your chest.",
                                         "Lifting your hips or feet off the floor."]))
        out.append(lyingPress(name: "Incline Barbell Press", id: "incline-barbell-press", incline: 40, dumbbells: false,
                              halfGrip: 0.35, template: .other,
                              muscles: ([.chest, .frontDelts], [.triceps]),
                              setup: ["Set the bench to about 40 degrees and plant your feet.",
                                      "Pull your shoulder blades back and down against the pad.",
                                      "Grip slightly wider than your shoulders and unrack."],
                              cues: ["Lower the bar to your upper chest.",
                                     "Keep your forearms vertical and elbows tucked at about 45 degrees.",
                                     "Press straight up until your arms lock out over your shoulders."],
                              mistakes: ["Setting the bench so steep it becomes a shoulder press.",
                                         "Lowering the bar to your neck or face.",
                                         "Lifting your head and hips off the bench."]))
        out.append(lyingPress(name: "Decline Bench Press", id: "decline-bench-press", incline: -20, dumbbells: false,
                              halfGrip: 0.35, template: .other,
                              muscles: ([.chest], [.triceps, .frontDelts]),
                              setup: ["Lock your legs under the pads and lie back on the decline bench.",
                                      "Pull your shoulder blades together against the pad.",
                                      "Grip just wider than shoulder-width and unrack with straight arms."],
                              cues: ["Lower the bar to your lower chest.",
                                     "Keep your forearms vertical and elbows tucked.",
                                     "Press up until your arms are fully locked out."],
                              mistakes: ["Letting the bar drift towards your neck.",
                                         "Using a decline steeper than needed.",
                                         "Bouncing the bar off your chest."]))
        out.append(lyingPress(name: "Close-Grip Bench Press", id: "close-grip-bench-press", incline: 0, dumbbells: false,
                              halfGrip: 0.16, template: .benchPress,
                              muscles: ([.triceps], [.chest, .frontDelts]),
                              setup: ["Lie on a flat bench with your feet planted and shoulder blades pinched.",
                                      "Grip the bar about shoulder-width apart, no narrower.",
                                      "Unrack the bar over your shoulders with straight arms."],
                              cues: ["Tuck your elbows close to your ribs as you lower.",
                                     "Touch the bar to your lower chest.",
                                     "Press up by driving through your triceps."],
                              mistakes: ["Gripping so narrow your wrists bend back.",
                                         "Flaring your elbows out wide.",
                                         "Letting the bar drift towards your neck."]))
        out.append(lyingPress(name: "Dumbbell Bench Press", id: "dumbbell-bench-press", incline: 0, dumbbells: true,
                              halfGrip: 0, template: .other,
                              muscles: ([.chest], [.frontDelts, .triceps]),
                              setup: ["Sit with the dumbbells on your thighs, then lie back and kick them up.",
                                      "Plant your feet and pull your shoulder blades together.",
                                      "Start with the dumbbells directly above your shoulders."],
                              cues: ["Lower the dumbbells to the sides of your chest.",
                                     "Keep your forearms vertical and elbows at about 45 degrees.",
                                     "Press up and slightly in until your arms are straight."],
                              mistakes: ["Letting your elbows flare out to the sides.",
                                         "Lowering the dumbbells too far and straining your shoulders.",
                                         "Letting the dumbbells drift apart as you press."]))
        out.append(lyingPress(name: "Incline Dumbbell Press", id: "incline-dumbbell-press", incline: 35, dumbbells: true,
                              halfGrip: 0, template: .other,
                              muscles: ([.chest, .frontDelts], [.triceps]),
                              setup: ["Set the bench to about 35 degrees and sit back with the dumbbells on your thighs.",
                                      "Kick the dumbbells up and pull your shoulder blades back.",
                                      "Turn your wrists slightly in so your palms face a little inward."],
                              cues: ["Lower the dumbbells to the sides of your upper chest.",
                                     "Keep your wrists stacked over your elbows.",
                                     "Press up and slightly in over your upper chest."],
                              mistakes: ["Setting the bench too steep.",
                                         "Bouncing the dumbbells at the bottom.",
                                         "Arching your lower back off the pad."]))
        out.append(dumbbellFlye())
        out.append(cableFlye())
        out.append(machineChestPress())
        out.append(pushUp())
        out.append(dips(name: "Dips (Chest)", id: "dips-chest", lean: 22, narrow: false))
        out.append(dips(name: "Tricep Dips", id: "tricep-dips", lean: 3, narrow: true))
        out.append(overheadPress())
        out.append(dumbbellShoulderPress())
        out.append(arnoldPress())
        out.append(machineShoulderPress())
        return out
    }

    // MARK: Lying presses

    /// Barbell or dumbbell press lying on a flat, inclined or declined bench. d: 0 = lockout, 1 = bottom.
    private static func lyingPress(name: String, id: String, incline: Float, dumbbells: Bool, halfGrip: Float,
                                   template: MotionTraits.Template,
                                   muscles: ([MuscleGroup], [MuscleGroup]),
                                   setup: [String], cues: [String], mistakes: [String]) -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.template = template
        traits.feetPlanted = true
        traits.onBench = true
        traits.bilateralBar = !dumbbells
        traits.drivingJoint = .leftWrist
        let rig = Rigs.lying(incline: incline)
        let close = halfGrip < 0.2 && !dumbbells
        let bottom = rig.chest + rig.front * 0.135 - rig.up * (close ? 0.24 : (incline > 10 ? 0.16 : 0.21))
        let top = V3(0, rig.chest.y + (incline < 5 ? 0.575 : 0.62), rig.chest.z + (incline > 10 ? -0.04 : 0.0))
        let axisAngle = Ease.rad(incline > 10 ? 35 : 8)
        return motion(name, id: id, duration: 4.2,
                      phases: [(0, "Arms locked out"), (0.5, "Bar at chest")],
                      primary: muscles.0, secondary: muscles.1,
                      camera: .side, focus: 0.75,
                      setup: setup, cues: cues, mistakes: mistakes, traits: traits) { t in
            let d = Ease.profile(t, hold: 0.08)
            var s = rig.spec
            let c = Ease.lerp(top, bottom, d)
            let poleL = V3(0.6 * (1 - d) + (close ? 0.1 : 0.25) * d, -1, 0.4 * (1 - d))
            var props = rig.props
            if dumbbells {
                let x = Ease.lerp(0.21, 0.32, d)
                s.leftArm = .reach(hand: V3(x, c.y, c.z), pole: poleL, handDir: V3(0, 1, 0))
                s.rightArm = .reach(hand: V3(-x, c.y, c.z), pole: mirrorX(poleL), handDir: V3(0, 1, 0))
                s.leftGrip = V3(cos(axisAngle), 0, sin(axisAngle))
                s.rightGrip = V3(cos(axisAngle), 0, -sin(axisAngle))
                props.append(.dumbbell(center: V3(x, c.y, c.z), axis: s.leftGrip))
                props.append(.dumbbell(center: V3(-x, c.y, c.z), axis: s.rightGrip))
            } else {
                s.gripBar(center: V3(0, c.y, c.z), halfGrip: halfGrip, handDir: V3(0, 1, 0), pole: poleL)
                props.append(Props.barbell(V3(0, c.y, c.z)))
                props.append(contentsOf: Props.rack(z: rig.chest.z - (incline > 10 ? 0.55 : 0.48), height: max(1.0, c.y - 0.05)))
            }
            return makeFrame(s, props)
        }
    }

    static func dumbbellFlye() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.onBench = true
        traits.drivingJoint = .leftWrist
        let rig = Rigs.lying(incline: 0)
        return motion("Dumbbell Flye", id: "dumbbell-flye", duration: 4.4,
                      phases: [(0, "Arms over chest"), (0.5, "Arms open wide")],
                      primary: [.chest], secondary: [.frontDelts],
                      camera: .front, focus: 0.8,
                      setup: ["Lie on a flat bench with a dumbbell in each hand and feet planted.",
                              "Press the dumbbells over your chest with palms facing each other.",
                              "Soften your elbows and keep that bend fixed."],
                      cues: ["Open your arms wide in a hugging arc.",
                             "Stop when your upper arms are level with your chest.",
                             "Squeeze your chest to bring the dumbbells back together."],
                      mistakes: ["Straightening your arms and straining your elbows.",
                                 "Dropping the dumbbells too far below the bench.",
                                 "Turning the flye into a press by bending your elbows."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.08)
            var s = rig.spec
            let a = Ease.lerp(0.04, 1.55, d)
            s.leftArm = .fkWorld(upper: V3(sin(a), cos(a), 0), elbowFlex: 0.45, bend: V3(-0.5, 1, 0))
            s.rightArm = .fkWorld(upper: V3(-sin(a), cos(a), 0), elbowFlex: 0.45, bend: V3(0.5, 1, 0))
            s.leftGrip = V3(0, 0, 1)
            s.rightGrip = V3(0, 0, 1)
            var props = rig.props
            let pose = FigureSolver.solve(s)
            props.append(.dumbbell(center: pose.position(.leftHand), axis: V3(0, 0, 1)))
            props.append(.dumbbell(center: pose.position(.rightHand), axis: V3(0, 0, 1)))
            return GuideFrame(pose: pose, props: props)
        }
    }

    // MARK: Standing / seated chest

    static func cableFlye() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Cable Flye", id: "cable-flye", duration: 4.2,
                      phases: [(0, "Arms wide"), (0.5, "Hands together")],
                      primary: [.chest], secondary: [.frontDelts],
                      camera: .front, focus: 1.2,
                      setup: ["Set both pulleys high and grab a handle in each hand.",
                              "Step forward into a split stance and lean slightly forward.",
                              "Start with your arms out wide and elbows softly bent."],
                      cues: ["Sweep your hands down and together in a hugging arc.",
                             "Keep the same soft bend in your elbows.",
                             "Squeeze your chest, then return slowly to the stretch."],
                      mistakes: ["Bending and straightening your elbows like a press.",
                                 "Leaning and swinging your body to pull the cables.",
                                 "Letting your arms go back past your shoulders."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec.standing()
            s.pelvis = V3(0, 0.92, 0.03)
            s.pelvisPitch = Ease.rad(15)
            s.headPitch = -0.2
            s.plantFeet(leftAnkle: V3(0.12, 0.08, 0.26), rightAnkle: V3(-0.12, 0.08, -0.20),
                        leftPole: V3(0.1, 0.3, 1), rightPole: V3(-0.1, 0.3, 1), toeOut: 6)
            let hand = V3(Ease.lerp(0.72, 0.06, d), Ease.lerp(1.30, 1.04, d), Ease.lerp(-0.02, 0.44, d))
            let pole = V3(0.5, -0.6, 0.5)
            s.leftArm = .reach(hand: hand, pole: pole, handDir: nil)
            s.rightArm = .reach(hand: mirrorX(hand), pole: mirrorX(pole), handDir: nil)
            s.leftGrip = V3(0, 0, 1)
            s.rightGrip = V3(0, 0, 1)
            var props: [GuideProp] = []
            for side in [Float(1), -1] {
                let h = V3(side * hand.x, hand.y, hand.z)
                props.append(.handle(center: h, axis: V3(0, 0, 1), length: 0.12))
                props.append(.cable(from: V3(side * 0.95, 1.95, 0), to: h))
                props.append(contentsOf: Props.tower(x: side * 0.95, z: 0.0, pulleyY: 1.95))
            }
            return makeFrame(s, props)
        }
    }

    static func machineChestPress() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.onBench = true
        traits.drivingJoint = .leftWrist
        let rig = Rigs.seated(seatTop: 0.45, backLean: 0, ankleZ: 0.40)
        return motion("Machine Chest Press", id: "machine-chest-press", duration: 4,
                      phases: [(0, "Handles at chest"), (0.5, "Arms extended")],
                      primary: [.chest], secondary: [.frontDelts, .triceps],
                      camera: .side, focus: 1.0,
                      setup: ["Adjust the seat so the handles line up with your mid chest.",
                              "Sit back with your shoulder blades against the pad and feet flat.",
                              "Grip the handles with your wrists straight."],
                      cues: ["Press the handles forward until your arms are nearly straight.",
                             "Keep your shoulder blades pinched against the pad.",
                             "Return slowly until you feel a light chest stretch."],
                      mistakes: ["Letting your shoulders roll forward.",
                                 "Locking your elbows hard at the end.",
                                 "Setting the seat so high you press with your shoulders."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = rig.spec
            let hand = V3(0.27, 1.00, Ease.lerp(0.24, 0.62, d))
            let pole = V3(0.3, -1, -0.2)
            s.leftArm = .reach(hand: hand, pole: pole, handDir: V3(0, 0, 1))
            s.rightArm = .reach(hand: mirrorX(hand), pole: mirrorX(pole), handDir: V3(0, 0, 1))
            s.leftGrip = V3(1, 0, 0)
            s.rightGrip = V3(1, 0, 0)
            var props = rig.props
            for side in [Float(1), -1] {
                let h = V3(side * hand.x, hand.y, hand.z)
                props.append(.handle(center: h, axis: V3(0, 0, 1), length: 0.12))
                props.append(Props.rod(V3(side * 0.34, 1.00, -0.30), h, 0.025))
            }
            props.append(Props.rod(V3(0.34, 0.95, -0.30), V3(-0.34, 0.95, -0.30), 0.03))
            props.append(Props.box(V3(0, 0.55, -0.62), V3(0.40, 0.90, 0.25), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .weightStack))
            return makeFrame(s, props)
        }
    }

    // MARK: Bodyweight pressing

    static func pushUp() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .chest
        return motion("Push-Up", id: "push-up", duration: 3.6,
                      phases: [(0, "Arms straight"), (0.5, "Chest near floor")],
                      primary: [.chest], secondary: [.triceps, .frontDelts, .abs],
                      camera: .side, focus: 0.45,
                      setup: ["Place your hands slightly wider than your shoulders under your chest.",
                              "Step your feet back so your body forms one straight line.",
                              "Brace your abs and squeeze your glutes."],
                      cues: ["Lower as one stiff plank until your chest is near the floor.",
                             "Keep your elbows at about 45 degrees to your body.",
                             "Push the floor away until your arms are straight."],
                      mistakes: ["Letting your hips sag or pike up.",
                                 "Flaring your elbows straight out to the sides.",
                                 "Only going halfway down."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            let alpha = Ease.rad(Ease.lerp(17.5, 2.5, d))
            let ay: Float = 0.16
            let az: Float = -1.20
            let body = V3(0, sin(alpha), cos(alpha))
            var s = PoseSpec()
            let ankleMid = V3(0, ay, az)
            s.pelvis = ankleMid + body * 0.85
            s.pelvisPitch = .pi / 2 - alpha
            let p = asin(ay / FigureProportions.foot)
            let foot = V3(0, -sin(p), -cos(p))
            s.leftLeg = .plant(ankle: V3(0.10, ay, az), pole: V3(0, -1, 0), footDir: foot)
            s.rightLeg = .plant(ankle: V3(-0.10, ay, az), pole: V3(0, -1, 0), footDir: foot)
            let hand = V3(0.30, 0.02, 0.18)
            let pole = V3(0.5, 0.2, -1)
            s.leftArm = .reach(hand: hand, pole: pole, handDir: V3(0, 0, 1))
            s.rightArm = .reach(hand: mirrorX(hand), pole: mirrorX(pole), handDir: V3(0, 0, 1))
            s.leftGrip = V3(1, 0, 0)
            s.rightGrip = V3(1, 0, 0)
            return makeFrame(s, [Props.floorMat(center: V3(0, 0.005, -0.5), size: SIMD2<Float>(0.9, 2.4))])
        }
    }

    static func dips(name: String, id: String, lean: Float, narrow: Bool) -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.drivingJoint = .chest
        let barX: Float = narrow ? 0.24 : 0.30
        return motion(name, id: id, duration: 4,
                      phases: [(0, "Arms locked out"), (0.5, "Lowest point")],
                      primary: narrow ? [.triceps] : [.chest, .triceps], secondary: narrow ? [.chest, .frontDelts] : [.frontDelts],
                      camera: .side, focus: 1.3,
                      setup: ["Grip the parallel bars and press up until your arms are straight.",
                              narrow ? "Keep your torso upright and cross your ankles behind you." : "Lean your torso slightly forward and cross your ankles behind you.",
                              "Keep your shoulders down and away from your ears."],
                      cues: ["Lower until your elbows reach about 90 degrees.",
                             narrow ? "Keep your elbows pointing straight back." : "Keep your chest leaning forward over the bars.",
                             "Press up until your arms are fully straight."],
                      mistakes: ["Dropping so low your shoulders strain.",
                                 "Swinging your legs to build momentum.",
                                 "Shrugging your shoulders up to your ears."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec()
            let chestY = Ease.lerp(1.78, 1.42, d)
            let chestZ = Ease.lerp(0.0, narrow ? 0.03 : 0.10, d)
            let l = Ease.rad(lean)
            let chest = V3(0, chestY, chestZ)
            s.pelvis = chest - V3(0, cos(l), sin(l)) * 0.5
            s.pelvisPitch = l
            s.headPitch = -0.1
            let down = V3(0, -0.7, -0.7)
            let anklePos = s.pelvis + V3(0, -0.45, -0.28)
            s.leftLeg = .plant(ankle: anklePos + V3(0.04, 0, 0), pole: V3(0.1, -0.2, 1), footDir: down)
            s.rightLeg = .plant(ankle: anklePos + V3(-0.04, 0, 0), pole: V3(-0.1, -0.2, 1), footDir: down)
            let hand = V3(barX, 1.15, 0)
            let hd = FigureSolver.safeNormalize(V3(0, -1, 0.2))
            s.leftArm = .reach(hand: hand, pole: V3(0.3, 0, -1), handDir: hd)
            s.rightArm = .reach(hand: mirrorX(hand), pole: V3(-0.3, 0, -1), handDir: hd)
            var props: [GuideProp] = []
            for side in [Float(1), -1] {
                props.append(Props.rod(V3(side * barX, 1.12, -0.35), V3(side * barX, 1.12, 0.45), 0.025))
                props.append(Props.rod(V3(side * barX, 0, -0.35), V3(side * barX, 1.12, -0.35), 0.04))
                props.append(Props.rod(V3(side * barX, 0, 0.45), V3(side * barX, 1.12, 0.45), 0.04))
            }
            props.append(Props.rod(V3(-barX, 0.02, -0.35), V3(barX, 0.02, -0.35), 0.03))
            props.append(Props.rod(V3(-barX, 0.02, 0.45), V3(barX, 0.02, 0.45), 0.03))
            return makeFrame(s, props)
        }
    }

    // MARK: Shoulder presses

    static func overheadPress() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.template = .overheadPress
        traits.feetPlanted = true
        traits.bilateralBar = true
        traits.drivingJoint = .leftWrist
        return motion("Overhead Press", id: "overhead-press", duration: 4,
                      phases: [(0, "Bar at collarbone"), (0.5, "Locked out overhead")],
                      primary: [.frontDelts], secondary: [.triceps, .sideDelts, .upperBack, .abs],
                      camera: .side, focus: 1.3,
                      setup: ["Set the bar at collarbone height and grip just outside your shoulders.",
                              "Lift it off the rack so it rests on your front delts.",
                              "Stand tall with feet hip-width, glutes and abs tight."],
                      cues: ["Press the bar straight up, moving your head back out of its path.",
                             "Lock out with the bar directly over your mid-foot.",
                             "Keep your ribs down and do not lean back."],
                      mistakes: ["Leaning back to push the bar up.",
                                 "Pressing the bar out in front of you.",
                                 "Flaring your ribs and arching your lower back."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec.standing(stance: 0.12)
            s.pelvisPitch = Ease.rad(-2)
            let y = Ease.lerp(1.50, 2.05, d)
            let z = 0.15 - 0.15 * Ease.ramp(d, from: 0.45, to: 1.0)
            let bar = V3(0, y, z)
            s.gripBar(center: bar, halfGrip: 0.30, handDir: V3(0, 1, 0), pole: V3(0.15, -1, 0.3))
            var props: [GuideProp] = [Props.barbell(bar)]
            props.append(contentsOf: Props.rack(z: -0.35, height: 1.35))
            return makeFrame(s, props)
        }
    }

    static func dumbbellShoulderPress() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.onBench = true
        traits.drivingJoint = .leftWrist
        let rig = Rigs.seated(seatTop: 0.45, backLean: 10, ankleZ: 0.38)
        let chest = FigureSolver.solve(rig.spec).position(.chest)
        return motion("Dumbbell Shoulder Press", id: "dumbbell-shoulder-press", duration: 4,
                      phases: [(0, "Dumbbells at shoulders"), (0.5, "Arms locked out")],
                      primary: [.frontDelts], secondary: [.triceps, .sideDelts],
                      camera: .front, focus: 1.3,
                      setup: ["Sit on a bench with the back pad nearly upright and feet flat.",
                              "Hold the dumbbells at shoulder height with palms facing forward.",
                              "Keep your forearms vertical and ribs down."],
                      cues: ["Press the dumbbells up until your arms are straight.",
                             "Bring them slightly together over your head.",
                             "Lower to shoulder height under control."],
                      mistakes: ["Arching your back off the pad.",
                                 "Letting the dumbbells drift forward.",
                                 "Stopping short of full lockout."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = rig.spec
            let x = Ease.lerp(0.28, 0.20, d)
            let hand = V3(x, Ease.lerp(chest.y + 0.10, chest.y + 0.62, d), Ease.lerp(chest.z + 0.10, chest.z + 0.03, d))
            let pole = V3(0.3, -1, 0)
            s.leftArm = .reach(hand: hand, pole: pole, handDir: V3(0, 1, 0))
            s.rightArm = .reach(hand: mirrorX(hand), pole: mirrorX(pole), handDir: V3(0, 1, 0))
            s.leftGrip = V3(1, 0, 0)
            s.rightGrip = V3(1, 0, 0)
            var props = rig.props
            props.append(.dumbbell(center: hand, axis: V3(1, 0, 0)))
            props.append(.dumbbell(center: mirrorX(hand), axis: V3(1, 0, 0)))
            return makeFrame(s, props)
        }
    }

    static func arnoldPress() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.onBench = true
        traits.drivingJoint = .leftWrist
        let rig = Rigs.seated(seatTop: 0.45, backLean: 10, ankleZ: 0.38)
        let chest = FigureSolver.solve(rig.spec).position(.chest)
        return motion("Arnold Press", id: "arnold-press", duration: 4.6,
                      phases: [(0, "Palms facing you"), (0.5, "Palms forward, locked out")],
                      primary: [.frontDelts, .sideDelts], secondary: [.triceps, .upperBack],
                      camera: .front, focus: 1.3,
                      setup: ["Sit on a bench with the back pad nearly upright.",
                              "Hold the dumbbells in front of your chest with palms facing you.",
                              "Keep your elbows in front of your body."],
                      cues: ["Rotate your palms outward as you press up.",
                             "Finish with palms forward and arms straight overhead.",
                             "Reverse the rotation smoothly on the way down."],
                      mistakes: ["Rushing the rotation so it becomes a swing.",
                                 "Arching your lower back.",
                                 "Letting the dumbbells crash together."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.08)
            var s = rig.spec
            let hand = V3(Ease.lerp(0.13, 0.22, d), Ease.lerp(chest.y + 0.22, chest.y + 0.62, d), Ease.lerp(chest.z + 0.28, chest.z + 0.03, d))
            let pole = V3(Ease.lerp(0.0, 0.3, d), -1, Ease.lerp(0.5, 0.0, d))
            s.leftArm = .reach(hand: hand, pole: pole, handDir: V3(0, 1, 0))
            s.rightArm = .reach(hand: mirrorX(hand), pole: mirrorX(pole), handDir: V3(0, 1, 0))
            let phi = Float.pi * Ease.ramp(d, from: 0.1, to: 0.9)
            s.leftGrip = V3(cos(phi), 0, sin(phi))
            s.rightGrip = V3(cos(phi), 0, -sin(phi))
            var props = rig.props
            props.append(.dumbbell(center: hand, axis: s.leftGrip))
            props.append(.dumbbell(center: mirrorX(hand), axis: s.rightGrip))
            return makeFrame(s, props)
        }
    }

    static func machineShoulderPress() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.onBench = true
        traits.drivingJoint = .leftWrist
        let rig = Rigs.seated(seatTop: 0.45, backLean: 5, ankleZ: 0.38)
        let chest = FigureSolver.solve(rig.spec).position(.chest)
        return motion("Machine Shoulder Press", id: "machine-shoulder-press", duration: 4,
                      phases: [(0, "Handles at shoulders"), (0.5, "Arms locked out")],
                      primary: [.frontDelts], secondary: [.triceps, .sideDelts],
                      camera: .side, focus: 1.3,
                      setup: ["Adjust the seat so the handles start level with your shoulders.",
                              "Sit tall with your back against the pad and feet flat.",
                              "Grip the handles with wrists stacked over elbows."],
                      cues: ["Press up until your arms are almost straight.",
                             "Keep your ribs down and your back on the pad.",
                             "Lower slowly to shoulder height."],
                      mistakes: ["Arching your back to push the handles.",
                                 "Shrugging your shoulders up as you press.",
                                 "Locking your elbows hard at the top."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = rig.spec
            let hand = V3(0.30, Ease.lerp(chest.y + 0.10, chest.y + 0.62, d), Ease.lerp(chest.z + 0.14, chest.z + 0.06, d))
            let pole = V3(0.3, -1, 0)
            s.leftArm = .reach(hand: hand, pole: pole, handDir: V3(0, 1, 0))
            s.rightArm = .reach(hand: mirrorX(hand), pole: mirrorX(pole), handDir: V3(0, 1, 0))
            var props = rig.props
            for side in [Float(1), -1] {
                let h = V3(side * hand.x, hand.y, hand.z)
                props.append(.handle(center: h, axis: V3(0, 0, 1), length: 0.12))
                props.append(Props.rod(V3(side * 0.42, h.y - 0.05, -0.28), h, 0.025))
            }
            props.append(Props.rod(V3(0.45, 0.45, -0.30), V3(0.45, 2.0, -0.30), 0.035))
            props.append(Props.rod(V3(-0.45, 0.45, -0.30), V3(-0.45, 2.0, -0.30), 0.035))
            props.append(Props.box(V3(0, 0.60, -0.70), V3(0.40, 0.90, 0.25), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .weightStack))
            return makeFrame(s, props)
        }
    }
}
