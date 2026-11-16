import Foundation
import simd

/// Rows, vertical pulls, face pulls and back extensions.
enum PullLibrary {

    static func all() -> [ExerciseGuideMotion] {
        [barbellRow(), tBarRow(), dumbbellRow(),
         pullUp(name: "Pull-Up", id: "pull-up", halfGrip: 0.32, supinated: false),
         pullUp(name: "Chin-Up", id: "chin-up", halfGrip: 0.14, supinated: true),
         latPulldown(), seatedCableRow(), facePull(), hyperextension()]
    }

    // MARK: Bent-over rows

    static func barbellRow() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.bilateralBar = true
        traits.drivingJoint = .leftWrist
        return motion("Barbell Row", id: "barbell-row", duration: 4,
                      phases: [(0, "Arms hanging"), (0.5, "Bar at belly")],
                      primary: [.lats, .upperBack], secondary: [.rearDelts, .biceps, .lowerBack, .forearms],
                      camera: .side, focus: 0.95,
                      setup: ["Stand with the bar over your mid-foot and grip just outside your knees.",
                              "Hinge until your torso is about 45 degrees and your back is flat.",
                              "Lift the bar so it hangs at arm's length below your chest."],
                      cues: ["Pull the bar to your lower ribs, driving your elbows back.",
                             "Hold your torso angle without heaving upward.",
                             "Lower the bar slowly until your arms are straight."],
                      mistakes: ["Standing up as you pull to swing the bar.",
                                 "Rounding your upper or lower back.",
                                 "Pulling the bar to your chest instead of your belly."]
                      , traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = Rigs.hinged(pitchDegrees: 50, pelvis: V3(0, 0.82, -0.25))
            s.headPitch = -0.35
            let base = FigureSolver.solve(s)
            let up = base.chestRotation.act(V3(0, 1, 0))
            let front = base.chestRotation.act(V3(0, 0, 1))
            let chest = base.position(.chest)
            let hangZ: Float = 0.12
            let start = V3(0, Rigs.hangBarY(shoulder: base.position(.leftShoulder), barZ: hangZ, halfGrip: 0.30), hangZ)
            let end = chest - up * 0.17 + front * 0.12
            let bar = Ease.lerp(start, end, d)
            let hd = FigureSolver.safeNormalize(Ease.lerp(V3(0, -1, 0.05), V3(0, -0.7, 0.7), d))
            s.gripBar(center: bar, halfGrip: 0.30, handDir: hd, pole: V3(0.4, 0.3, -1))
            return makeFrame(s, [Props.barbell(bar)])
        }
    }

    static func tBarRow() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("T-Bar Row", id: "t-bar-row", duration: 4,
                      phases: [(0, "Arms hanging"), (0.5, "Handle at chest")],
                      primary: [.upperBack, .lats], secondary: [.rearDelts, .biceps, .lowerBack],
                      camera: .side, focus: 0.9,
                      setup: ["Straddle the bar with your feet shoulder-width apart.",
                              "Hinge until your torso is about 45 degrees with a flat back.",
                              "Grip the handle with straight arms and your chest up."],
                      cues: ["Pull the handle towards your lower chest.",
                             "Drive your elbows back and squeeze your shoulder blades.",
                             "Lower under control without rounding your back."],
                      mistakes: ["Jerking the weight up with your hips.",
                                 "Rounding your back at the bottom.",
                                 "Shrugging instead of pulling your elbows back."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = Rigs.hinged(pitchDegrees: 52, pelvis: V3(0, 0.82, -0.25), stance: 0.15)
            s.headPitch = -0.38
            let base = FigureSolver.solve(s)
            let up = base.chestRotation.act(V3(0, 1, 0))
            let front = base.chestRotation.act(V3(0, 0, 1))
            let chest = base.position(.chest)
            let start = V3(0, Rigs.hangBarY(shoulder: base.position(.leftShoulder), barZ: 0.14, halfGrip: 0.07), 0.14)
            let end = chest - up * 0.14 + front * 0.12
            let hand = Ease.lerp(start, end, d)
            let hd = FigureSolver.safeNormalize(Ease.lerp(V3(0, -1, 0.05), V3(0, -0.7, 0.7), d))
            s.gripBar(center: hand, axis: V3(1, 0, 0), halfGrip: 0.07, handDir: hd, pole: V3(0.5, 0.3, -1))
            let pivot = V3(0, 0.12, -1.0)
            let barPoint = hand - V3(0, 0.28, 0)
            let u = simd_normalize(barPoint - pivot)
            let end2 = pivot + u * 1.75
            var props: [GuideProp] = [
                .barbell(center: (pivot + end2) / 2, axis: u, length: 1.75, plateRadius: 0),
                .cylinder(from: end2 - u * 0.16, to: end2 - u * 0.04, radius: 0.20, kind: .platform),
                .handle(center: hand, axis: V3(1, 0, 0), length: 0.18),
                Props.rod(barPoint, hand - V3(0, 0.03, 0), 0.02),
                Props.rod(V3(0.12, 0, pivot.z), V3(-0.12, 0, pivot.z), 0.04)
            ]
            props.append(Props.box(V3(0, 0.06, pivot.z), V3(0.3, 0.12, 0.25), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .platform))
            return makeFrame(s, props)
        }
    }

    static func dumbbellRow() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.onBench = true
        traits.drivingJoint = .rightWrist
        return motion("Dumbbell Row", id: "dumbbell-row", duration: 4,
                      phases: [(0, "Arm hanging"), (0.5, "Elbow past torso")],
                      primary: [.lats, .upperBack], secondary: [.rearDelts, .biceps, .forearms],
                      camera: .threeQuarter, focus: 0.8,
                      setup: ["Place one knee and the same-side hand on a flat bench.",
                              "Plant your other foot on the floor and keep your back flat.",
                              "Let the dumbbell hang straight down from your shoulder."],
                      cues: ["Pull the dumbbell towards your hip, elbow close to your side.",
                             "Keep your torso level and still.",
                             "Lower slowly until your arm is straight."],
                      mistakes: ["Twisting your torso to heave the weight up.",
                                 "Pulling towards your chest instead of your hip.",
                                 "Letting your lower back sag."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec()
            s.pelvis = V3(0.04, 0.92, -0.05)
            s.pelvisPitch = Ease.rad(78)
            s.headPitch = -0.7
            s.leftLeg = .plant(ankle: V3(0.14, 0.53, -0.44), pole: V3(0, -1, 0.1), footDir: V3(0, -0.2, -0.98))
            s.rightLeg = .plant(ankle: V3(-0.16, 0.08, 0.10), pole: V3(-0.2, 0.2, 1), footDir: FigureSolver.footDir(side: -1, toeOutDegrees: 10))
            let base = FigureSolver.solve(s)
            let sh = base.position(.rightShoulder)
            let hang = V3(sh.x, sh.y - 0.62, sh.z + 0.04)
            let top = V3(sh.x - 0.02, sh.y - 0.20, sh.z - 0.52)
            let hand = Ease.lerp(hang, top, d)
            s.rightArm = .reach(hand: hand, pole: V3(-0.2, 0.4, -1), handDir: V3(0, -1, 0.1))
            let benchHand = V3(0.12, 0.45 + 0.02, sh.z + 0.0)
            s.leftArm = .reach(hand: benchHand, pole: V3(0.4, 0, -1), handDir: V3(0, 0, 1))
            s.rightGrip = V3(0, 0, 1)
            var props = Props.flatBench(padTop: 0.45, zMin: -0.65, zMax: 0.55, width: 0.30)
            props = props.map { prop in
                if case let .box(c, sz, r, k) = prop { return .box(center: c + V3(0.14, 0, 0), size: sz, rotation: r, kind: k) }
                if case let .cylinder(a, b, r, k) = prop { return .cylinder(from: a + V3(0.14, 0, 0), to: b + V3(0.14, 0, 0), radius: r, kind: k) }
                return prop
            }
            props.append(.dumbbell(center: hand, axis: V3(0, 0, 1)))
            return makeFrame(s, props)
        }
    }

    // MARK: Vertical pulls

    static func pullUp(name: String, id: String, halfGrip: Float, supinated: Bool) -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.template = .pullUp
        traits.drivingJoint = .chest
        let barY: Float = 2.30
        return motion(name, id: id, duration: 4.4,
                      phases: [(0, "Dead hang"), (0.5, "Chin over bar")],
                      primary: [.lats], secondary: supinated ? [.biceps, .upperBack, .forearms] : [.upperBack, .biceps, .forearms],
                      camera: .side, focus: 1.55,
                      setup: [supinated ? "Grip the bar with palms facing you, hands shoulder-width apart."
                                        : "Grip the bar with palms facing away, slightly wider than your shoulders.",
                              "Hang with your arms straight and shoulders pulled down.",
                              "Cross your ankles behind you and tighten your core."],
                      cues: ["Pull your elbows down to your sides.",
                             "Lift your chest towards the bar until your chin clears it.",
                             "Lower slowly to a full hang."],
                      mistakes: ["Kicking or swinging to gain momentum.",
                                 "Stopping before your chin clears the bar.",
                                 "Shrugging your shoulders up by your ears."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec()
            let chestY = Ease.lerp(1.70, 2.17, d)
            let chestZ = Ease.lerp(-0.03, supinated ? -0.14 : -0.12, d)
            let lean = Ease.rad(Ease.lerp(-6, supinated ? -14 : -9, d))
            let chest = V3(0, chestY, chestZ)
            s.pelvisPitch = lean
            s.pelvis = chest - V3(0, cos(lean), sin(lean)) * 0.5
            s.headPitch = Ease.lerp(0.0, -0.3, d)
            let ankle = s.pelvis + V3(0, -0.52, -0.40)
            let down = FigureSolver.safeNormalize(V3(0, -0.8, -0.6))
            s.leftLeg = .plant(ankle: ankle + V3(0.04, 0, 0), pole: V3(0.1, -0.1, 1), footDir: down)
            s.rightLeg = .plant(ankle: ankle + V3(-0.04, 0, 0), pole: V3(-0.1, -0.1, 1), footDir: down)
            let bar = V3(0, barY, 0)
            s.gripBar(center: bar, halfGrip: halfGrip, handDir: V3(0, 1, 0.2), pole: V3(0.7, -0.5, -0.3))
            var props: [GuideProp] = [Props.rod(V3(-0.65, barY, 0), V3(0.65, barY, 0), 0.02, .frame)]
            props.append(Props.rod(V3(0.65, 0, 0), V3(0.65, barY, 0), 0.04))
            props.append(Props.rod(V3(-0.65, 0, 0), V3(-0.65, barY, 0), 0.04))
            props.append(Props.rod(V3(0.65, 0.02, -0.5), V3(0.65, 0.02, 0.5), 0.03))
            props.append(Props.rod(V3(-0.65, 0.02, -0.5), V3(-0.65, 0.02, 0.5), 0.03))
            return makeFrame(s, props)
        }
    }

    static func latPulldown() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.onBench = true
        traits.drivingJoint = .leftWrist
        let rig = Rigs.seated(seatTop: 0.50, backLean: 12, ankleZ: 0.40, withBackPad: false)
        let chest = FigureSolver.solve(rig.spec).position(.chest)
        return motion("Lat Pulldown", id: "lat-pulldown", duration: 4,
                      phases: [(0, "Arms overhead"), (0.5, "Bar at upper chest")],
                      primary: [.lats], secondary: [.biceps, .upperBack, .rearDelts],
                      camera: .side, focus: 1.3,
                      setup: ["Adjust the thigh pad so it holds you firmly in the seat.",
                              "Grip the bar wider than your shoulders and sit tall.",
                              "Lean back slightly and start with arms stretched overhead."],
                      cues: ["Pull the bar to your upper chest by driving your elbows down.",
                             "Keep your chest up and torso still.",
                             "Let the bar rise slowly until your arms are straight."],
                      mistakes: ["Leaning far back to yank the bar down.",
                                 "Pulling the bar behind your neck.",
                                 "Letting the bar bounce off your chest."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = rig.spec
            let top = V3(0, chest.y + 0.58, chest.z + 0.10)
            let bottom = V3(0, chest.y + 0.03, chest.z + 0.15)
            let bar = Ease.lerp(top, bottom, d)
            s.gripBar(center: bar, halfGrip: 0.36, handDir: V3(0, 1, 0), pole: V3(0.4, -1, -0.2))
            var props = rig.props
            props.append(.handle(center: bar, axis: V3(1, 0, 0), length: 1.0))
            props.append(.cable(from: V3(0, 2.55, 0.0), to: bar))
            props.append(Props.rod(V3(-0.25, 0.80, 0.28), V3(0.25, 0.80, 0.28), 0.05, .pad))
            props.append(Props.rod(V3(0.25, 0.80, 0.28), V3(0.25, 0.80, 0.0), 0.03))
            props.append(Props.rod(V3(-0.25, 0.80, 0.28), V3(-0.25, 0.80, 0.0), 0.03))
            props.append(contentsOf: Props.tower(x: 0, z: -0.45, pulleyY: 2.55))
            return makeFrame(s, props)
        }
    }

    // MARK: Seated and standing cable pulls

    static func seatedCableRow() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.onBench = true
        traits.drivingJoint = .leftWrist
        var rig = Rigs.seated(seatTop: 0.25, backLean: 0, pelvisZ: 0, ankleX: 0.17, ankleY: 0.32, ankleZ: 0.78, withBackPad: false)
        let foot = FigureSolver.safeNormalize(V3(0, 0.91, 0.40))
        rig.spec.leftLeg = .plant(ankle: V3(0.17, 0.32, 0.78), pole: V3(0.1, 1, 0), footDir: foot)
        rig.spec.rightLeg = .plant(ankle: V3(-0.17, 0.32, 0.78), pole: V3(-0.1, 1, 0), footDir: foot)
        let chest = FigureSolver.solve(rig.spec).position(.chest)
        return motion("Seated Cable Row", id: "seated-cable-row", duration: 4,
                      phases: [(0, "Arms extended"), (0.5, "Handle at belly")],
                      primary: [.upperBack, .lats], secondary: [.rearDelts, .biceps, .lowerBack],
                      camera: .side, focus: 0.7,
                      setup: ["Sit tall with your feet on the plate and knees slightly bent.",
                              "Hold the handle with arms straight in front of you.",
                              "Brace your abs and keep your chest up."],
                      cues: ["Pull the handle to your belly, elbows past your torso.",
                             "Squeeze your shoulder blades together.",
                             "Return slowly without leaning forward."],
                      mistakes: ["Rocking your torso back and forth.",
                                 "Shrugging your shoulders towards your ears.",
                                 "Letting your back round at full stretch."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = rig.spec
            let hand = V3(0.06, chest.y - 0.23, Ease.lerp(chest.z + 0.54, chest.z + 0.15, d))
            let pole = V3(0.4, 0.2, -1)
            let hd = V3(0, -0.1, 1)
            s.leftArm = .reach(hand: hand, pole: pole, handDir: hd)
            s.rightArm = .reach(hand: mirrorX(hand), pole: mirrorX(pole), handDir: hd)
            s.leftGrip = V3(0, 0, 1)
            s.rightGrip = V3(0, 0, 1)
            var props = rig.props
            let mid = V3(0, hand.y, hand.z)
            props.append(.handle(center: mid, axis: V3(1, 0, 0), length: 0.22))
            props.append(.cable(from: V3(0, 0.35, 1.70), to: mid))
            props.append(Props.box(V3(0, 0.45, 0.88), V3(0.55, 0.50, 0.06), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .platform))
            props.append(Props.box(V3(0, 0.12, 0.4), V3(0.5, 0.10, 1.6), simd_quatf(angle: 0, axis: V3(0, 1, 0)), .frame))
            props.append(contentsOf: Props.tower(x: 0, z: 1.75, pulleyY: 0.35))
            return makeFrame(s, props)
        }
    }

    static func facePull() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .leftWrist
        return motion("Face Pull", id: "face-pull", duration: 4,
                      phases: [(0, "Arms extended"), (0.5, "Hands by ears")],
                      primary: [.rearDelts, .upperBack], secondary: [.traps, .biceps],
                      camera: .threeQuarter, focus: 1.4,
                      setup: ["Set the cable at head height and attach a rope.",
                              "Hold the rope ends and step back until your arms are straight.",
                              "Stand tall with a slight lean back and soft knees."],
                      cues: ["Pull the rope towards your face, hands splitting past your ears.",
                             "Keep your elbows high and out wide.",
                             "Squeeze your upper back, then return slowly."],
                      mistakes: ["Leaning back and using body weight.",
                                 "Pulling to your chest with low elbows.",
                                 "Using a weight that stops your elbows rising."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec.standing()
            s.pelvisPitch = Ease.rad(-4)
            let hand = V3(Ease.lerp(0.07, 0.30, d), Ease.lerp(1.42, 1.62, d), Ease.lerp(0.55, 0.12, d))
            let pole = V3(1, 0, -0.3)
            let hd = FigureSolver.safeNormalize(Ease.lerp(V3(0, 0, 1), V3(0, 0.7, 0.7), d))
            s.leftArm = .reach(hand: hand, pole: pole, handDir: hd)
            s.rightArm = .reach(hand: mirrorX(hand), pole: mirrorX(pole), handDir: mirrorX(hd))
            s.leftGrip = V3(0, 0, 1)
            s.rightGrip = V3(0, 0, 1)
            var props: [GuideProp] = []
            for side in [Float(1), -1] {
                let h = V3(side * hand.x, hand.y, hand.z)
                props.append(.handle(center: h, axis: V3(0, 0, 1), length: 0.10))
                props.append(.cable(from: V3(side * 0.04, 1.65, 1.60), to: h))
            }
            props.append(contentsOf: Props.tower(x: 0, z: 1.65, pulleyY: 1.65))
            return makeFrame(s, props)
        }
    }

    // MARK: Back extension

    static func hyperextension() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.drivingJoint = .head
        let legDir = FigureSolver.safeNormalize(V3(0, -0.57, -0.82))
        let pelvis = V3(0, 0.95, 0)
        let ankle = pelvis + legDir * 0.84
        return motion("Hyperextension", id: "hyperextension", duration: 4.2,
                      phases: [(0, "Body in a line"), (0.5, "Hinged forward")],
                      primary: [.lowerBack, .glutes], secondary: [.hamstrings],
                      camera: .side, focus: 0.9,
                      setup: ["Set the pad just below your hip bones and hook your heels under the rollers.",
                              "Cross your arms over your chest.",
                              "Start with your body in one straight line."],
                      cues: ["Hinge forward at your hips with a straight back.",
                             "Lower until you feel a hamstring stretch.",
                             "Squeeze your glutes to return to a straight line, not higher."],
                      mistakes: ["Rounding your back at the bottom.",
                                 "Leaning back past a straight line at the top.",
                                 "Swinging up with momentum."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            var s = PoseSpec()
            s.pelvis = pelvis
            let foot = FigureSolver.safeNormalize(V3(0, -0.5, -0.85))
            s.leftLeg = .plant(ankle: ankle + V3(0.10, 0, 0), pole: V3(0, -1, 0.3), footDir: foot)
            s.rightLeg = .plant(ankle: ankle + V3(-0.10, 0, 0), pole: V3(0, -1, 0.3), footDir: foot)
            s.pelvisPitch = Ease.rad(Ease.lerp(55, 108, d))
            s.headPitch = -Ease.rad(Ease.lerp(0, 40, d))
            let first = FigureSolver.solve(s)
            let rot = first.chestRotation
            let chest = first.position(.chest)
            let hand = chest + rot.act(V3(0.12, 0.02, 0.17))
            s.leftArm = .reach(hand: hand, pole: V3(0.3, 0.2, -0.5), handDir: rot.act(V3(-1, 0, 0)))
            s.rightArm = .reach(hand: mirrorSide(hand, chest, rot), pole: V3(-0.3, 0.2, -0.5), handDir: rot.act(V3(1, 0, 0)))
            // The pad is part of the machine: it stays put while the lifter hinges over it.
            let front = FigureSolver.qx(Ease.rad(55)).act(V3(0, 0, 1))
            let padCenter = pelvis + front * 0.14 + legDir * 0.12
            var props: [GuideProp] = [
                Props.box(padCenter, V3(0.34, 0.40, 0.08), Props.orient(y: -legDir, zHint: front)),
                Props.rod(ankle + V3(-0.22, 0.10, -0.06), ankle + V3(0.22, 0.10, -0.06), 0.04, .pad),
                Props.rod(ankle + V3(-0.22, 0.10, 0.10), ankle + V3(0.22, 0.10, 0.10), 0.04, .pad),
                Props.rod(V3(0.15, 0, 0.30), padCenter - front * 0.05, 0.03),
                Props.rod(V3(-0.15, 0, 0.30), padCenter - front * 0.05, 0.03),
                Props.rod(V3(0.15, 0, -0.9), ankle + V3(0.22, 0.0, -0.1), 0.03),
                Props.rod(V3(-0.15, 0, -0.9), ankle + V3(-0.22, 0.0, -0.1), 0.03)
            ]
            props.append(Props.rod(V3(-0.3, 0.02, 0.3), V3(0.3, 0.02, 0.3), 0.03))
            return makeFrame(s, props)
        }
    }

    private static func mirrorSide(_ p: V3, _ chest: V3, _ rot: simd_quatf) -> V3 {
        let local = rot.inverse.act(p - chest)
        return chest + rot.act(V3(-local.x, local.y, local.z))
    }
}
