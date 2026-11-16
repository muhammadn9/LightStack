import Foundation
import simd

/// Curls, triceps work, raises, shrugs and upright rows.
enum ArmLibrary {

    static func all() -> [ExerciseGuideMotion] {
        var out: [ExerciseGuideMotion] = []
        out.append(barbellCurl())
        out.append(dumbbellCurl(name: "Dumbbell Curl", id: "dumbbell-curl", hammer: false))
        out.append(dumbbellCurl(name: "Hammer Curl", id: "hammer-curl", hammer: true))
        out.append(preacherCurl())
        out.append(cableCurl())
        out.append(concentrationCurl())
        out.append(inclineDumbbellCurl())
        out.append(tricepPushdown())
        out.append(skullCrusher())
        out.append(overheadTricepExtension())
        out.append(cableOverheadExtension())
        out.append(kickback())
        out.append(lateralRaise())
        out.append(cableLateralRaise())
        out.append(frontRaise())
        out.append(reverseFlye())
        out.append(uprightRow())
        out.append(shrugs())
        return out
    }

    private static func curlTraits(bar: Bool) -> MotionTraits {
        var t = MotionTraits()
        t.template = .curl
        t.feetPlanted = true
        t.bilateralBar = bar
        t.drivingJoint = .leftWrist
        return t
    }

    private static let zAxis = V3(0, 0, 1)
    private static let xAxis = V3(1, 0, 0)

    // MARK: Curls

    static func barbellCurl() -> ExerciseGuideMotion {
        motion("Barbell Curl", id: "barbell-curl", duration: 4,
               phases: [(0, "Arms straight"), (0.5, "Squeeze at top")],
               primary: [.biceps], secondary: [.forearms, .frontDelts], camera: .side, focus: 1.0,
               setup: ["Stand tall, feet shoulder-width apart, knees soft.",
                       "Hold the bar with an underhand grip, hands shoulder-width apart.",
                       "Pin your elbows to your sides with the bar on your thighs."],
               cues: ["Keep your elbows glued to your sides.",
                      "Curl the bar up in a smooth arc to shoulder height.",
                      "Squeeze your biceps, then lower slowly for a count of three."],
               mistakes: ["Swinging your torso to get the bar up.",
                          "Letting your elbows drift forward as you curl.",
                          "Dropping the bar fast instead of lowering it under control."],
               traits: curlTraits(bar: true)) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec.standing()
            s.armsFKWorld(upper: v3(0, -1, 0.02), flex: Ease.lerp(0.08, 2.35, d), bend: v3(0, 0, 1))
            let pose = FigureSolver.solve(s)
            let mid = (pose.position(.leftHand) + pose.position(.rightHand)) / 2
            return GuideFrame(pose: pose, props: [Props.barbell(mid)])
        }
    }

    static func dumbbellCurl(name: String, id: String, hammer: Bool) -> ExerciseGuideMotion {
        motion(name, id: id, duration: 4,
               phases: [(0, "Arms straight"), (0.5, "Squeeze at top")],
               primary: hammer ? [.biceps, .forearms] : [.biceps], secondary: hammer ? [.frontDelts] : [.forearms, .frontDelts],
               camera: hammer ? .threeQuarter : .side, focus: 1.0,
               setup: ["Stand tall with a dumbbell in each hand, feet shoulder-width apart.",
                       hammer ? "Hold the dumbbells with palms facing each other." : "Let your arms hang with palms facing your thighs.",
                       "Pin your elbows to your sides."],
               cues: hammer ? ["Keep your palms facing each other all the way up.",
                               "Keep your elbows still and tight to your ribs.",
                               "Lower slowly until your arms are fully straight."]
                            : ["Turn your palms up as you curl.",
                               "Keep your elbows still and tight to your ribs.",
                               "Lower slowly until your arms are fully straight."],
               mistakes: ["Swinging your body to lift the weights.",
                          "Letting your elbows drift forward.",
                          "Cutting the bottom of each rep short."],
               traits: curlTraits(bar: false)) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec.standing()
            s.armsFKWorld(upper: v3(0, -1, 0.02), flex: Ease.lerp(0.08, 2.35, d), bend: v3(0, 0, 1))
            let sigma = hammer ? 0 : (.pi / 2) * Ease.ramp(d, from: 0.05, to: 0.75)
            s.leftGrip = V3(sin(sigma), 0, cos(sigma))
            s.rightGrip = V3(sin(sigma), 0, -cos(sigma))
            let pose = FigureSolver.solve(s)
            return GuideFrame(pose: pose, props: [.dumbbell(center: pose.position(.leftHand), axis: pose.leftGripAxis),
                                                  .dumbbell(center: pose.position(.rightHand), axis: pose.rightGripAxis)])
        }
    }

    static func preacherCurl() -> ExerciseGuideMotion {
        var traits = curlTraits(bar: true)
        traits.onBench = true
        return motion("Preacher Curl", id: "preacher-curl", duration: 4,
               phases: [(0, "Arms extended"), (0.5, "Squeeze at top")],
               primary: [.biceps], secondary: [.forearms],
               camera: .side, focus: 0.95,
               setup: ["Adjust the seat so your armpits rest on top of the pad.",
                       "Lay your upper arms flat on the pad.",
                       "Hold the bar with an underhand, shoulder-width grip."],
               cues: ["Keep the backs of your arms pressed into the pad.",
                      "Curl up until the bar nears your chin.",
                      "Lower slowly to almost straight arms."],
               mistakes: ["Lifting your elbows off the pad.",
                          "Dropping the bar fast at the bottom.",
                          "Leaning back to cheat the weight up."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec()
            s.pelvis = V3(0, 0.55, -0.25)
            s.leftLeg = .plant(ankle: V3(0.20, 0.08, 0.15), pole: V3(0.2, 1, 0.3), footDir: FigureSolver.footDir(side: 1))
            s.rightLeg = .plant(ankle: V3(-0.20, 0.08, 0.15), pole: V3(-0.2, 1, 0.3), footDir: FigureSolver.footDir(side: -1))
            let u = V3(0, -0.707, 0.707)
            let b = V3(0, 0.707, 0.707)
            s.armsFKWorld(upper: u, flex: Ease.lerp(0.10, 2.25, d), bend: b)
            let pose = FigureSolver.solve(s)
            let mid = (pose.position(.leftHand) + pose.position(.rightHand)) / 2
            let shoulder = (pose.position(.leftShoulder) + pose.position(.rightShoulder)) / 2
            let n = V3(0, 0.707, 0.707)
            let padCenter = shoulder + u * 0.20 - n * 0.085
            let props: [GuideProp] = [
                .ezBar(center: mid, axis: xAxis),
                Props.box(padCenter, V3(0.45, 0.55, 0.08), Props.orient(y: u, zHint: n)),
                Props.rod(padCenter - u * 0.2 - n * 0.04, V3(0, 0, padCenter.z - 0.1), 0.04),
                Props.box(V3(0, 0.40, -0.25), V3(0.40, 0.10, 0.40)),
                Props.rod(V3(0, 0, -0.25), V3(0, 0.35, -0.25), 0.04)
            ]
            return GuideFrame(pose: pose, props: props)
        }
    }

    static func cableCurl() -> ExerciseGuideMotion {
        motion("Cable Curl", id: "cable-curl", duration: 4,
               phases: [(0, "Arms straight"), (0.5, "Squeeze at top")],
               primary: [.biceps], secondary: [.forearms],
               camera: .side, focus: 1.0,
               setup: ["Set the pulley at the bottom and attach a straight bar.",
                       "Stand a step back so the cable stays tight.",
                       "Hold the bar underhand with your elbows at your sides."],
               cues: ["Keep tension on the cable the whole rep.",
                      "Curl until your forearms are close to vertical.",
                      "Lower slowly without letting the stack touch."],
               mistakes: ["Leaning back as you curl.",
                          "Letting your elbows slide forward.",
                          "Standing too close so the cable goes slack."],
               traits: curlTraits(bar: false)) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec.standing()
            s.armsFKWorld(upper: v3(0, -1, 0.02), flex: Ease.lerp(0.08, 2.35, d), bend: v3(0, 0, 1))
            let pose = FigureSolver.solve(s)
            let mid = (pose.position(.leftHand) + pose.position(.rightHand)) / 2
            var props: [GuideProp] = [.handle(center: mid, axis: xAxis, length: 0.50),
                                      .cable(from: V3(0, 0.25, 0.90), to: mid)]
            props.append(contentsOf: Props.tower(x: 0, z: 1.0, pulleyY: 0.25))
            return GuideFrame(pose: pose, props: props)
        }
    }

    static func concentrationCurl() -> ExerciseGuideMotion {
        var traits = curlTraits(bar: false)
        traits.feetPlanted = true
        traits.onBench = true
        traits.drivingJoint = .rightWrist
        return motion("Concentration Curl", id: "concentration-curl", duration: 4,
               phases: [(0, "Arm hanging"), (0.5, "Squeeze at top")],
               primary: [.biceps], secondary: [.forearms],
               camera: .threeQuarter, focus: 0.7,
               setup: ["Sit on a bench with your feet wide and a dumbbell in one hand.",
                       "Lean forward and rest the back of that upper arm on your inner thigh.",
                       "Let the dumbbell hang with your arm fully straight."],
               cues: ["Keep your upper arm pressed against your thigh.",
                      "Curl the dumbbell up towards your shoulder.",
                      "Squeeze at the top, then lower slowly."],
               mistakes: ["Lifting your elbow off your thigh.",
                          "Rocking your torso to help the lift.",
                          "Rushing the lowering phase."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec()
            s.pelvis = V3(0, 0.55, 0)
            s.pelvisPitch = Ease.rad(45)
            s.headPitch = -0.6
            s.leftLeg = .plant(ankle: V3(0.40, 0.08, 0.30), pole: V3(0.6, 1, 0.3), footDir: FigureSolver.footDir(side: 1, toeOutDegrees: 25))
            s.rightLeg = .plant(ankle: V3(-0.40, 0.08, 0.30), pole: V3(-0.6, 1, 0.3), footDir: FigureSolver.footDir(side: -1, toeOutDegrees: 25))
            s.rightArm = .fkWorld(upper: V3(0.06, -0.93, -0.36), elbowFlex: Ease.lerp(0.08, 2.40, d), bend: V3(0, 0, 1))
            let first = FigureSolver.solve(s)
            let knee = first.position(.leftKnee)
            s.leftArm = .reach(hand: knee + V3(0, 0.07, 0), pole: V3(0.6, 0.2, -1), handDir: nil)
            let sigma = (.pi / 2) * Ease.ramp(d, from: 0.05, to: 0.75)
            s.rightGrip = V3(sin(sigma), 0, -cos(sigma))
            let pose = FigureSolver.solve(s)
            var props = Props.flatBench(padTop: 0.45, zMin: -0.45, zMax: 0.25, width: 0.35)
            props.append(.dumbbell(center: pose.position(.rightHand), axis: pose.rightGripAxis))
            return GuideFrame(pose: pose, props: props)
        }
    }

    static func inclineDumbbellCurl() -> ExerciseGuideMotion {
        var traits = curlTraits(bar: false)
        traits.onBench = true
        return motion("Incline Dumbbell Curl", id: "incline-dumbbell-curl", duration: 4.4,
               phases: [(0, "Arms hanging"), (0.5, "Squeeze at top")],
               primary: [.biceps], secondary: [.forearms],
               camera: .side, focus: 0.8,
               setup: ["Set a bench to about 55 degrees and sit back against it.",
                       "Let your arms hang straight down behind your torso.",
                       "Hold dumbbells with palms facing forward."],
               cues: ["Keep your upper arms hanging still.",
                      "Curl up without moving your elbows forward.",
                      "Lower all the way for a full stretch."],
               mistakes: ["Swinging the elbows forward.",
                          "Lifting your back off the bench.",
                          "Using weights so heavy the range shrinks."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            let rig = Rigs.lying(incline: 55)
            var s = rig.spec
            s.armsFKWorld(upper: v3(0.02, -1, -0.12), flex: Ease.lerp(0.08, 2.30, d), bend: v3(0, 0, 1))
            let sigma = (.pi / 2) * Ease.ramp(d, from: 0.05, to: 0.75)
            s.leftGrip = V3(sin(sigma), 0, cos(sigma))
            s.rightGrip = V3(sin(sigma), 0, -cos(sigma))
            let pose = FigureSolver.solve(s)
            var props = rig.props
            props.append(.dumbbell(center: pose.position(.leftHand), axis: pose.leftGripAxis))
            props.append(.dumbbell(center: pose.position(.rightHand), axis: pose.rightGripAxis))
            return GuideFrame(pose: pose, props: props)
        }
    }

    // MARK: Triceps

    static func tricepPushdown() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Tricep Pushdown", id: "tricep-pushdown", duration: 3.6,
               phases: [(0, "Forearms level"), (0.5, "Arms straight")],
               primary: [.triceps], secondary: [.forearms],
               camera: .side, focus: 1.0,
               setup: ["Set the pulley high and attach a rope or bar.",
                       "Stand close with a slight forward lean and feet hip-width.",
                       "Pin your elbows to your sides with forearms level."],
               cues: ["Keep your elbows pinned to your ribs.",
                      "Push down until your arms are fully straight.",
                      "Let the handle rise only to forearm level."],
               mistakes: ["Letting your elbows flare or drift forward.",
                          "Leaning over the bar to push with body weight.",
                          "Stopping short of full arm extension."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec.standing()
            s.pelvisPitch = Ease.rad(8)
            s.headPitch = -0.12
            s.armsFKWorld(upper: v3(0.04, -1, 0.0), flex: Ease.lerp(1.75, 0.10, d), bend: v3(0, 0, 1))
            let pose = FigureSolver.solve(s)
            let mid = (pose.position(.leftHand) + pose.position(.rightHand)) / 2
            var props: [GuideProp] = [.handle(center: mid, axis: xAxis, length: 0.45),
                                      .cable(from: V3(0, 2.15, 0.38), to: mid)]
            props.append(contentsOf: Props.tower(x: 0, z: 0.45, pulleyY: 2.15))
            return GuideFrame(pose: pose, props: props)
        }
    }

    static func skullCrusher() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.onBench = true
        traits.bilateralBar = true
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Skull Crusher", id: "skull-crusher", duration: 4,
               phases: [(0, "Arms vertical"), (0.5, "Bar by forehead")],
               primary: [.triceps], secondary: [.forearms, .frontDelts],
               camera: .side, focus: 0.9,
               setup: ["Lie on a flat bench holding an EZ bar with a narrow overhand grip.",
                       "Press the bar over your shoulders with arms straight.",
                       "Plant your feet flat on the floor."],
               cues: ["Keep your upper arms still and pointing up.",
                      "Bend only at the elbows to lower the bar to your forehead.",
                      "Press back up by straightening your elbows."],
               mistakes: ["Flaring your elbows out wide.",
                          "Letting your upper arms drift back over your head.",
                          "Using so much weight your wrists collapse."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.08)
            let rig = Rigs.lying(incline: 0)
            var s = rig.spec
            s.armsFKWorld(upper: v3(0, 1, -0.10), flex: Ease.lerp(0.12, 1.75, d), bend: v3(0, 0, -1))
            let pose = FigureSolver.solve(s)
            let mid = (pose.position(.leftHand) + pose.position(.rightHand)) / 2
            let axis = simd_normalize(pose.position(.leftHand) - pose.position(.rightHand))
            var props = rig.props
            props.append(.ezBar(center: mid, axis: axis))
            return GuideFrame(pose: pose, props: props)
        }
    }

    static func overheadTricepExtension() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Overhead Tricep Extension", id: "overhead-tricep-extension", duration: 4,
               phases: [(0, "Arms overhead"), (0.5, "Dumbbell behind head")],
               primary: [.triceps], secondary: [.forearms, .frontDelts],
               camera: .side, focus: 1.3,
               setup: ["Stand tall and hold one dumbbell with both hands under the top plate.",
                       "Press it overhead with your arms straight.",
                       "Brace your abs and keep your ribs down."],
               cues: ["Keep your elbows pointing forward, close to your ears.",
                      "Lower the dumbbell behind your head by bending your elbows.",
                      "Press up until your arms are fully straight."],
               mistakes: ["Letting your elbows flare out wide.",
                          "Arching your lower back as you press.",
                          "Moving your upper arms instead of just the forearms."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.08)
            var s = PoseSpec.standing()
            let hand = V3(0.05, Ease.lerp(2.05, 1.50, d), Ease.lerp(0.04, -0.17, d))
            let pole = V3(0.3, 1, 0.2)
            let dir = FigureSolver.safeNormalize(V3(0, 1, Ease.lerp(0.1, 0.9, d)))
            s.leftArm = .reach(hand: hand, pole: pole, handDir: dir)
            s.rightArm = .reach(hand: mirrorX(hand), pole: mirrorX(pole), handDir: dir)
            let pose = FigureSolver.solve(s)
            let mid = (pose.position(.leftHand) + pose.position(.rightHand)) / 2
            return GuideFrame(pose: pose, props: [.dumbbell(center: mid - V3(0, 0.08, 0), axis: V3(0, 1, 0))])
        }
    }

    static func cableOverheadExtension() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Cable Overhead Extension", id: "cable-overhead-extension", duration: 4,
               phases: [(0, "Rope behind head"), (0.5, "Arms extended")],
               primary: [.triceps], secondary: [.forearms],
               camera: .side, focus: 1.3,
               setup: ["Set the pulley low and attach a rope.",
                       "Face away from the stack, holding the rope behind your head.",
                       "Take a split stance and lean forward slightly."],
               cues: ["Keep your elbows high and pointing forward.",
                      "Extend your arms forward and up until straight.",
                      "Return slowly until you feel a deep triceps stretch."],
               mistakes: ["Letting your elbows drop and flare.",
                          "Using your back to pull the rope forward.",
                          "Standing too close so the cable goes slack."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.08)
            var s = PoseSpec.standing()
            s.pelvis = V3(0, 0.925, 0.05)
            s.pelvisPitch = Ease.rad(12)
            s.headPitch = -0.2
            s.plantFeet(leftAnkle: V3(0.12, 0.08, 0.30), rightAnkle: V3(-0.12, 0.08, -0.20),
                        leftPole: V3(0.1, 0.3, 1), rightPole: V3(-0.1, 0.3, 1), toeOut: 6)
            let hand = V3(0.05, Ease.lerp(1.92, 1.52, d), Ease.lerp(0.30, -0.10, d))
            let dir = FigureSolver.safeNormalize(V3(0, 1, Ease.lerp(0.35, 0.9, d)))
            let pole = V3(0.3, 1, 0.1)
            s.leftArm = .reach(hand: hand, pole: pole, handDir: dir)
            s.rightArm = .reach(hand: mirrorX(hand), pole: mirrorX(pole), handDir: dir)
            let pose = FigureSolver.solve(s)
            let mid = (pose.position(.leftHand) + pose.position(.rightHand)) / 2
            var props: [GuideProp] = [.handle(center: mid, axis: xAxis, length: 0.30),
                                      .cable(from: V3(0, 0.30, -0.95), to: mid)]
            props.append(contentsOf: Props.tower(x: 0, z: -1.0, pulleyY: 0.30))
            return GuideFrame(pose: pose, props: props)
        }
    }

    static func kickback() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Kickback", id: "kickback", duration: 3.6,
               phases: [(0, "Forearms down"), (0.5, "Arms straight back")],
               primary: [.triceps], secondary: [.rearDelts],
               camera: .side, focus: 0.9,
               setup: ["Hold a dumbbell in each hand and hinge forward at the hips.",
                       "Keep your back flat and knees slightly bent.",
                       "Raise your elbows until your upper arms are in line with your torso."],
               cues: ["Keep your upper arms still and level with your back.",
                      "Straighten your elbows to swing the dumbbells back.",
                      "Squeeze your triceps, then lower under control."],
               mistakes: ["Letting your elbows drop towards the floor.",
                          "Swinging your whole arm instead of just the forearm.",
                          "Rounding your back."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = Rigs.hinged(pitchDegrees: 62, pelvis: V3(0, 0.80, -0.22))
            s.headPitch = -0.5
            s.armsFKWorld(upper: v3(0.02, -0.45, -0.89), flex: Ease.lerp(1.65, 0.20, d), bend: v3(0, -1, 0))
            s.leftGrip = V3(0, 0, 1)
            s.rightGrip = V3(0, 0, 1)
            let pose = FigureSolver.solve(s)
            return GuideFrame(pose: pose, props: [.dumbbell(center: pose.position(.leftHand), axis: zAxis),
                                                  .dumbbell(center: pose.position(.rightHand), axis: zAxis)])
        }
    }

    // MARK: Raises

    static func lateralRaise() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.template = .lateralRaise
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Lateral Raise", id: "lateral-raise", duration: 4,
               phases: [(0, "Arms at sides"), (0.5, "Shoulder height")],
               primary: [.sideDelts], secondary: [.traps, .frontDelts],
               camera: .front, focus: 1.1,
               setup: ["Stand tall with a dumbbell in each hand at your sides.",
                       "Lean forward slightly and soften your elbows.",
                       "Keep your feet shoulder-width apart."],
               cues: ["Lift your elbows out to the sides, leading with the elbows.",
                      "Stop when your hands reach shoulder height.",
                      "Lower slowly over three seconds."],
               mistakes: ["Swinging your torso to throw the weights up.",
                          "Raising your hands above shoulder height.",
                          "Shrugging your shoulders towards your ears."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec.standing()
            s.pelvisPitch = Ease.rad(8)
            s.headPitch = -0.12
            let e = Ease.lerp(0.12, 1.50, d)
            s.armsFK(upper: V3(sin(e), -cos(e), 0), flex: 0.25, bend: V3(0, 0, 1))
            s.leftGrip = V3(0, 0, 1)
            s.rightGrip = V3(0, 0, 1)
            let pose = FigureSolver.solve(s)
            return GuideFrame(pose: pose, props: [.dumbbell(center: pose.position(.leftHand), axis: zAxis),
                                                  .dumbbell(center: pose.position(.rightHand), axis: zAxis)])
        }
    }

    static func cableLateralRaise() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Cable Lateral Raise", id: "cable-lateral-raise", duration: 4,
               phases: [(0, "Hand across body"), (0.5, "Shoulder height")],
               primary: [.sideDelts], secondary: [.traps],
               camera: .front, focus: 1.1,
               setup: ["Set the pulley low and stand side-on to the stack.",
                       "Hold the handle with your far hand and grip the frame with the other.",
                       "Stand tall with a slight lean away from the stack."],
               cues: ["Lead with your elbow, keeping a soft bend.",
                      "Raise until your hand is at shoulder height.",
                      "Lower slowly and keep tension on the cable."],
               mistakes: ["Jerking the cable with your body.",
                          "Lifting your hand far above shoulder height.",
                          "Standing so close the cable slackens."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec.standing()
            let e = Ease.lerp(0.10, 1.50, d)
            s.leftArm = .fk(upper: V3(sin(e), -cos(e), 0), elbowFlex: 0.25, bend: V3(0, 0, 1))
            s.rightArm = .reach(hand: V3(-0.45, 1.22, 0.15), pole: V3(-0.3, -0.5, -1), handDir: nil)
            s.leftGrip = V3(0, 0, 1)
            let pose = FigureSolver.solve(s)
            let hand = pose.position(.leftHand)
            var props: [GuideProp] = [.handle(center: hand, axis: zAxis, length: 0.14),
                                      .cable(from: V3(-0.70, 0.25, 0.15), to: hand)]
            props.append(contentsOf: Props.tower(x: -0.72, z: 0.15, pulleyY: 0.25))
            return GuideFrame(pose: pose, props: props)
        }
    }

    static func frontRaise() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Front Raise", id: "front-raise", duration: 4,
               phases: [(0, "Arms down"), (0.5, "Shoulder height")],
               primary: [.frontDelts], secondary: [.sideDelts, .upperBack],
               camera: .side, focus: 1.1,
               setup: ["Stand tall with a dumbbell in each hand in front of your thighs.",
                       "Keep a slight bend in your elbows.",
                       "Brace your abs and keep your feet shoulder-width apart."],
               cues: ["Raise both dumbbells in front of you to shoulder height.",
                      "Keep your torso still and your ribs down.",
                      "Lower slowly under control."],
               mistakes: ["Leaning back to swing the weights up.",
                          "Lifting the weights above eye level.",
                          "Using weights too heavy to control."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec.standing()
            let e = Ease.lerp(0.14, 1.50, d)
            s.armsFK(upper: V3(0.04, -cos(e), sin(e)), flex: 0.20, bend: V3(0, 1, 0.2))
            let sigma = (.pi / 2) * Ease.ramp(d, from: 0.05, to: 0.8)
            s.leftGrip = V3(sin(sigma), 0, cos(sigma))
            s.rightGrip = V3(sin(sigma), 0, -cos(sigma))
            let pose = FigureSolver.solve(s)
            return GuideFrame(pose: pose, props: [.dumbbell(center: pose.position(.leftHand), axis: pose.leftGripAxis),
                                                  .dumbbell(center: pose.position(.rightHand), axis: pose.rightGripAxis)])
        }
    }

    static func reverseFlye() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Reverse Flye", id: "reverse-flye", duration: 4,
               phases: [(0, "Arms hanging"), (0.5, "Arms out wide")],
               primary: [.rearDelts], secondary: [.upperBack, .traps],
               camera: .back, focus: 0.95,
               setup: ["Hold a dumbbell in each hand and hinge forward until your torso is nearly flat.",
                       "Keep your back straight, knees soft and neck neutral.",
                       "Let your arms hang below your chest."],
               cues: ["Lift your arms out wide with a soft bend in your elbows.",
                      "Squeeze your shoulder blades together at the top.",
                      "Lower slowly without swinging."],
               mistakes: ["Standing up to heave the weights.",
                          "Shrugging your shoulders.",
                          "Bending your elbows into a row."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = Rigs.hinged(pitchDegrees: 68, pelvis: V3(0, 0.80, -0.22))
            s.headPitch = -0.55
            let a = Ease.lerp(0.14, 1.42, d)
            s.armsFKWorld(upper: V3(sin(a), -cos(a), 0), flex: 0.30, bend: V3(0, -0.4, 1))
            s.leftGrip = V3(0, 0, 1)
            s.rightGrip = V3(0, 0, 1)
            let pose = FigureSolver.solve(s)
            return GuideFrame(pose: pose, props: [.dumbbell(center: pose.position(.leftHand), axis: zAxis),
                                                  .dumbbell(center: pose.position(.rightHand), axis: zAxis)])
        }
    }

    static func uprightRow() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.bilateralBar = true
        traits.drivingJoint = .leftWrist
        return motion("Upright Row", id: "upright-row", duration: 4,
               phases: [(0, "Bar at thighs"), (0.5, "Elbows high")],
               primary: [.sideDelts, .traps], secondary: [.biceps, .forearms, .frontDelts],
               camera: .front, focus: 1.1,
               setup: ["Stand tall holding a barbell with an overhand grip, hands about shoulder-width apart.",
                       "Let the bar rest against your thighs.",
                       "Keep your knees soft and ribs down."],
               cues: ["Pull the bar up close to your body, leading with your elbows.",
                      "Stop around chest height with elbows above your wrists.",
                      "Lower the bar slowly to your thighs."],
               mistakes: ["Pulling the bar higher than your collarbone.",
                          "Swinging your hips to jerk the bar up.",
                          "Gripping so narrow that your wrists strain."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec.standing()
            let bar = V3(0, Ease.lerp(0.80, 1.30, d), 0.14)
            let hd = FigureSolver.safeNormalize(V3(0, Ease.lerp(-1, 1, Ease.smooth(d)), 0.25))
            s.gripBar(center: bar, halfGrip: 0.16, handDir: hd, pole: V3(1, 0.4, -0.2))
            let pose = FigureSolver.solve(s)
            return GuideFrame(pose: pose, props: [Props.barbell(bar)])
        }
    }

    static func shrugs() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Shrugs", id: "shrugs", duration: 3.2,
               phases: [(0, "Shoulders relaxed"), (0.5, "Shoulders lifted")],
               primary: [.traps], secondary: [.forearms, .upperBack],
               camera: .front, focus: 1.1,
               setup: ["Stand tall holding a dumbbell in each hand at your sides.",
                       "Keep your arms straight and chest up.",
                       "Place your feet shoulder-width apart."],
               cues: ["Lift your shoulders straight up towards your ears.",
                      "Hold the top for a second and squeeze.",
                      "Lower slowly until your shoulders fully relax."],
               mistakes: ["Rolling your shoulders in circles.",
                          "Bending your elbows to help lift the weight.",
                          "Jutting your head forward."],
               traits: traits) { t in
            let d = Ease.profile(t, hold: 0.12)
            var s = PoseSpec.standing()
            s.shoulderLift = Ease.lerp(-0.03, 0.06, d)
            s.armsFK(upper: V3(0.02, -1, 0), flex: 0.05, bend: V3(0, 0, 1))
            s.leftGrip = V3(0, 0, 1)
            s.rightGrip = V3(0, 0, 1)
            let pose = FigureSolver.solve(s)
            return GuideFrame(pose: pose, props: [.dumbbell(center: pose.position(.leftHand), axis: zAxis),
                                                  .dumbbell(center: pose.position(.rightHand), axis: zAxis)])
        }
    }
}
