import Foundation
import simd

/// Looping cardio cycles. One rep = one full cycle (a stride pair, a stroke, a pedal turn, a hop...).
/// Cycles are shown slower than real life so the movement is easy to read.
enum CardioLibrary {

    static func all() -> [ExerciseGuideMotion]  {
        [treadmillRun(), rowingMachine(), stairmaster(), cycling(), jumpRope(), battleRopes(), elliptical()]
    }

    private static let identity = simd_quatf(angle: 0, axis: V3(0, 1, 0))

    private static func cardioTraits(_ joint: GuideJoint) -> MotionTraits {
        var t = MotionTraits()
        t.drivingJoint = joint
        t.minPath = 0.30
        return t
    }

    // MARK: Treadmill

    /// Ankle position and foot pitch for one leg at gait phase `phase` (0...1). Stance first, then swing.
    private static func gait(_ phase: Float, stride s: Float) -> (z: Float, y: Float, pitch: Float) {
        let ph = phase - floor(phase)
        let flat = FigureProportions.flatFootPitch
        if ph < 0.40 {
            return (s - 2 * s * (ph / 0.40), 0.08, flat)
        }
        let u = (ph - 0.40) / 0.60
        let z = -s + 2 * s * Ease.smooth(u)
        let y = 0.08 + 0.26 * sin(.pi * u)
        return (z, y, Ease.lerp(flat, 0.10, sin(.pi * u)))
    }

    static func treadmillRun() -> ExerciseGuideMotion {
        let traits = cardioTraits(.leftAnkle)
        return motion("Treadmill Run", id: "treadmill-run", duration: 1.8,
                      phases: [(0, "Left foot strikes"), (0.5, "Right foot strikes")],
                      primary: [.quads, .hamstrings, .calves], secondary: [.glutes, .hipFlexors, .abs],
                      camera: .side, focus: 0.9,
                      setup: ["Stand on the belt with feet hip-width apart and hold the rails to start.",
                              "Start at a walk, then build to a comfortable run.",
                              "Stand tall with eyes forward and shoulders relaxed."],
                      cues: ["Land softly under your hips, not out in front.",
                             "Keep a slight forward lean from your ankles.",
                             "Swing your arms back and forth, elbows at about 90 degrees."],
                      mistakes: ["Over-striding so your heel lands far ahead of you.",
                                 "Gripping the rails while running.",
                                 "Hunching your shoulders and looking down."],
                      traits: traits) { t in
            var s = PoseSpec()
            s.pelvis = V3(0, 0.88 + 0.02 * cos(4 * .pi * t), 0)
            s.pelvisPitch = Ease.rad(7)
            s.headPitch = -0.1
            let l = gait(t, stride: 0.24)
            let r = gait(t + 0.5, stride: 0.24)
            let ld = FigureSolver.footDir(side: 1, toeOutDegrees: 4, pitch: l.pitch)
            let rd = FigureSolver.footDir(side: -1, toeOutDegrees: 4, pitch: r.pitch)
            s.leftLeg = .plant(ankle: V3(0.11, l.y, l.z), pole: V3(0.1, 0.2, 1), footDir: ld)
            s.rightLeg = .plant(ankle: V3(-0.11, r.y, r.z), pole: V3(-0.1, 0.2, 1), footDir: rd)
            let swing = 0.55 * cos(2 * .pi * t)
            s.leftArm = .fk(upper: V3(0.05, -cos(-swing), sin(-swing)), elbowFlex: 1.55, bend: V3(0, 0, 1))
            s.rightArm = .fk(upper: V3(-0.05, -cos(swing), sin(swing)), elbowFlex: 1.55, bend: V3(0, 0, 1))
            var props: [GuideProp] = [
                Props.box(V3(0, -0.02, 0.0), V3(0.60, 0.04, 1.80), identity, .platform),
                Props.rod(V3(0.34, 0.9, 0.55), V3(0.34, 0.9, 0.95), 0.02),
                Props.rod(V3(-0.34, 0.9, 0.55), V3(-0.34, 0.9, 0.95), 0.02),
                Props.rod(V3(0.34, 0, 0.95), V3(0.34, 1.2, 0.95), 0.03),
                Props.rod(V3(-0.34, 0, 0.95), V3(-0.34, 1.2, 0.95), 0.03)
            ]
            props.append(Props.box(V3(0, 1.25, 0.95), V3(0.5, 0.22, 0.12), identity, .frame))
            return makeFrame(s, props)
        }
    }

    // MARK: Rowing

    static func rowingMachine() -> ExerciseGuideMotion {
        var traits = cardioTraits(.pelvis)
        traits.maxStep = 0.16   // the arms and torso swing through about a metre of travel in half a stroke
        traits.feetPlanted = true
        traits.onBench = true
        return motion("Rowing Machine", id: "rowing-machine", duration: 3.8,
                      phases: [(0, "Catch"), (0.5, "Finish"), (0.75, "Recovery")],
                      primary: [.quads, .lats, .glutes], secondary: [.upperBack, .biceps, .hamstrings, .abs],
                      camera: .side, focus: 0.7,
                      setup: ["Strap your feet in and sit on the seat with shins vertical.",
                              "Hold the handle with straight arms and your torso leaning slightly forward.",
                              "Keep your back flat and chest up."],
                      cues: ["Drive with your legs first, then swing your torso back, then pull with your arms.",
                             "Reverse the order on the way back: arms, torso, then knees.",
                             "Finish with the handle at your lower ribs and elbows tucked."],
                      mistakes: ["Pulling with your arms before your legs have pushed.",
                                 "Rounding your back at the catch.",
                                 "Leaning too far back at the finish."],
                      traits: traits) { t in
            let d = t < 0.5 ? Ease.smooth(t / 0.5) : Ease.smooth(1 - (t - 0.5) / 0.5)
            let legs = Ease.clamp01(d / 0.65)
            let torso = Ease.clamp01((d - 0.15) / 0.80)
            let arms = Ease.clamp01((d - 0.40) / 0.60)
            var s = PoseSpec()
            let pz = Ease.lerp(0.52, 0.07, legs)
            s.pelvis = V3(0, 0.35, pz)
            let lean = Ease.rad(Ease.lerp(20, -22, torso))
            s.pelvisPitch = lean
            s.headPitch = -lean * 0.4
            let foot = FigureSolver.safeNormalize(V3(0, 0.80, 0.60))
            s.leftLeg = .plant(ankle: V3(0.17, 0.33, 0.90), pole: V3(0.1, 1, 0.2), footDir: foot)
            s.rightLeg = .plant(ankle: V3(-0.17, 0.33, 0.90), pole: V3(-0.1, 1, 0.2), footDir: foot)
            let base = FigureSolver.solve(s)
            let chest = base.position(.chest)
            let far = V3(0.14, chest.y - 0.22, chest.z + 0.54)
            let near = V3(0.14, chest.y - 0.30, chest.z + 0.16)
            let hand = Ease.lerp(far, near, arms)
            let hd = V3(0, 0, 1)
            s.leftArm = .reach(hand: hand, pole: V3(0.5, 0.3, -1), handDir: hd)
            s.rightArm = .reach(hand: mirrorX(hand), pole: V3(-0.5, 0.3, -1), handDir: hd)
            let mid = V3(0, hand.y, hand.z)
            var props: [GuideProp] = [
                .handle(center: mid, axis: V3(1, 0, 0), length: 0.50),
                .cable(from: V3(0, 0.45, 1.30), to: mid),
                Props.box(V3(0, 0.20, pz), V3(0.36, 0.08, 0.32), identity, .pad),
                Props.box(V3(0, 0.10, 0.50), V3(0.10, 0.08, 2.0), identity, .frame),
                Props.box(V3(0, 0.40, 0.97), V3(0.50, 0.40, 0.04), identity, .platform),
                .cylinder(from: V3(-0.18, 0.45, 1.45), to: V3(0.18, 0.45, 1.45), radius: 0.24, kind: .frame)
            ]
            props.append(Props.rod(V3(0.3, 0, 1.3), V3(0.3, 0.45, 1.45), 0.03))
            return makeFrame(s, props)
        }
    }

    // MARK: Stairs

    static func stairmaster() -> ExerciseGuideMotion {
        var traits = cardioTraits(.leftAnkle)
        traits.minPath = 0.30
        return motion("Stairmaster", id: "stairmaster", duration: 2.4,
                      phases: [(0, "Left step down"), (0.5, "Right step down")],
                      primary: [.quads, .glutes], secondary: [.hamstrings, .calves],
                      camera: .side, focus: 0.9,
                      setup: ["Step onto the pedals and hold the rails lightly for balance.",
                              "Stand tall with your hips under your shoulders.",
                              "Set a pace you can keep for the whole session."],
                      cues: ["Press through your whole foot on each step.",
                             "Keep your torso tall and your weight over your feet.",
                             "Use the rails for balance only, not to hold your weight."],
                      mistakes: ["Leaning heavily on the rails.",
                                 "Stepping on your toes only.",
                                 "Slouching forward over the console."],
                      traits: traits) { t in
            let c = cos(2 * .pi * t)
            let yl = 0.31 + 0.10 * c
            let yr = 0.31 - 0.10 * c
            var s = PoseSpec()
            s.pelvis = V3(0, 1.00, 0.04)
            s.pelvisPitch = Ease.rad(6)
            let dir = FigureSolver.footDir(side: 1, toeOutDegrees: 4)
            s.leftLeg = .plant(ankle: V3(0.13, yl + 0.0, 0.20), pole: V3(0.1, 0.2, 1), footDir: dir)
            s.rightLeg = .plant(ankle: V3(-0.13, yr + 0.0, 0.20), pole: V3(-0.1, 0.2, 1), footDir: V3(-dir.x, dir.y, dir.z))
            let hand = V3(0.30, 1.18, 0.34)
            s.leftArm = .reach(hand: hand, pole: V3(0.4, -1, -0.4), handDir: V3(0, 0, 1))
            s.rightArm = .reach(hand: mirrorX(hand), pole: V3(-0.4, -1, -0.4), handDir: V3(0, 0, 1))
            var props: [GuideProp] = [
                Props.box(V3(0.13, yl - 0.08 - 0.03, 0.22), V3(0.24, 0.06, 0.34), identity, .platform),
                Props.box(V3(-0.13, yr - 0.08 - 0.03, 0.22), V3(0.24, 0.06, 0.34), identity, .platform),
                Props.rod(V3(0.32, 1.18, 0.10), V3(0.32, 1.18, 0.60), 0.02),
                Props.rod(V3(-0.32, 1.18, 0.10), V3(-0.32, 1.18, 0.60), 0.02),
                Props.rod(V3(0.32, 0, 0.62), V3(0.32, 1.35, 0.62), 0.03),
                Props.rod(V3(-0.32, 0, 0.62), V3(-0.32, 1.35, 0.62), 0.03)
            ]
            props.append(Props.box(V3(0, 1.40, 0.62), V3(0.50, 0.20, 0.10), identity, .frame))
            props.append(Props.box(V3(0, 0.05, 0.30), V3(0.60, 0.10, 0.55), identity, .frame))
            return makeFrame(s, props)
        }
    }

    // MARK: Bike

    static func cycling() -> ExerciseGuideMotion {
        var traits = cardioTraits(.leftAnkle)
        traits.onBench = true
        return motion("Cycling", id: "cycling", duration: 2.0,
                      phases: [(0, "Left pedal at the top"), (0.5, "Right pedal at the top")],
                      primary: [.quads, .glutes], secondary: [.hamstrings, .calves],
                      camera: .side, focus: 0.8,
                      setup: ["Set the saddle so your knee is slightly bent at the bottom of the pedal stroke.",
                              "Rest your hands lightly on the handlebars.",
                              "Place the balls of your feet over the pedals."],
                      cues: ["Push down and pull through the whole circle, not just the downstroke.",
                             "Keep your knees tracking straight over your feet.",
                             "Keep your upper body relaxed and your hips still."],
                      mistakes: ["Setting the saddle so low your knees bend sharply.",
                                 "Bouncing in the saddle at high speed.",
                                 "Gripping the bars tightly with locked arms."],
                      traits: traits) { t in
            let bb = V3(0, 0.30, 0.18)
            let crank: Float = 0.175
            func pedal(_ th: Float) -> V3 { bb + V3(0, crank * sin(th), crank * cos(th)) }
            let thL = 2 * .pi * t + .pi / 2
            let thR = thL + .pi
            let pl = pedal(thL), pr = pedal(thR)
            let fd = FigureSolver.footDir(side: 1, toeOutDegrees: 0, pitch: 0.26)
            let fdR = V3(0, fd.y, fd.z)
            var s = PoseSpec()
            s.pelvis = V3(0, 0.96, -0.17)
            s.pelvisPitch = Ease.rad(38)
            s.headPitch = -0.5
            s.leftLeg = .plant(ankle: V3(0.10, pl.y, pl.z) - fd * FigureProportions.foot + V3(0, 0, 0), pole: V3(0.3, 0.6, 1), footDir: fd)
            s.rightLeg = .plant(ankle: V3(-0.10, pr.y, pr.z) - fdR * FigureProportions.foot, pole: V3(-0.3, 0.6, 1), footDir: fdR)
            let bar = V3(0.20, 1.06, 0.50)
            s.leftArm = .reach(hand: bar, pole: V3(0.5, -0.3, -0.5), handDir: V3(0, 0, 1))
            s.rightArm = .reach(hand: mirrorX(bar), pole: V3(-0.5, -0.3, -0.5), handDir: V3(0, 0, 1))
            var props: [GuideProp] = [
                Props.rod(V3(0.10, pl.y, pl.z), bb + V3(0.06, 0, 0), 0.015),
                Props.rod(V3(-0.10, pr.y, pr.z), bb + V3(-0.06, 0, 0), 0.015),
                Props.box(V3(0.10, pl.y - 0.02, pl.z), V3(0.10, 0.03, 0.10), identity, .platform),
                Props.box(V3(-0.10, pr.y - 0.02, pr.z), V3(0.10, 0.03, 0.10), identity, .platform),
                Props.box(V3(0, 0.86, -0.17), V3(0.12, 0.05, 0.26), identity, .pad),
                Props.rod(V3(0, 0.30, 0.18), V3(0, 0.84, -0.20), 0.025),
                Props.rod(V3(0, 0.30, 0.18), V3(0, 0.95, 0.55), 0.03),
                Props.rod(V3(0, 0.95, 0.55), V3(0, 1.06, 0.50), 0.025),
                Props.rod(V3(-0.22, 1.06, 0.50), V3(0.22, 1.06, 0.50), 0.015)
            ]
            props.append(.cylinder(from: V3(0.04, 0.34, 0.80), to: V3(-0.04, 0.34, 0.80), radius: 0.34, kind: .frame))
            props.append(.cylinder(from: V3(0.04, 0.34, -0.55), to: V3(-0.04, 0.34, -0.55), radius: 0.34, kind: .frame))
            return makeFrame(s, props)
        }
    }

    // MARK: Jump rope

    static func jumpRope() -> ExerciseGuideMotion {
        let traits = cardioTraits(.leftWrist)
        return motion("Jump Rope", id: "jump-rope", duration: 1.2,
                      phases: [(0, "Landing"), (0.5, "In the air")],
                      primary: [.calves], secondary: [.quads, .forearms, .sideDelts, .abs],
                      camera: .side, focus: 0.9,
                      setup: ["Hold the handles at hip height with elbows close to your sides.",
                              "Stand tall with feet together and knees soft.",
                              "Check the rope reaches your armpits when you stand on its middle."],
                      cues: ["Jump only a couple of centimetres, just enough for the rope to pass.",
                             "Turn the rope with your wrists, not your whole arms.",
                             "Land softly on the balls of your feet."],
                      mistakes: ["Jumping high and wasting energy.",
                                 "Swinging your arms in big circles.",
                                 "Landing flat-footed with stiff knees."],
                      traits: traits) { t in
            let hop = 0.05 * (0.5 - 0.5 * cos(2 * .pi * t))
            var s = PoseSpec()
            s.pelvis = V3(0, 0.90 + hop, 0)
            let ay = 0.08 + hop
            let heading = V3(0, 0, 1)
            let dl = FigureSolver.groundedFootDir(heading: heading, ankleY: ay, desiredPitch: FigureProportions.flatFootPitch + 0.6 * hop / 0.05 * 0.3)
            s.leftLeg = .plant(ankle: V3(0.10, ay, 0), pole: V3(0.1, 0.2, 1), footDir: dl)
            s.rightLeg = .plant(ankle: V3(-0.10, ay, 0), pole: V3(-0.1, 0.2, 1), footDir: dl)
            let ang = 2 * .pi * t
            let hand = V3(0.32, 1.02 + 0.07 * sin(ang), 0.10 + 0.07 * cos(ang))
            s.leftArm = .reach(hand: hand, pole: V3(0.3, -1, -0.2), handDir: nil)
            s.rightArm = .reach(hand: mirrorX(hand), pole: V3(-0.3, -1, -0.2), handDir: nil)
            // Rope: a loop swinging around the body, drawn as short taut segments.
            var props: [GuideProp] = []
            let n = 20
            let centre = V3(0, 1.0, 0.0)
            let psi0 = ang + .pi
            var prev = hand
            for k in 1...n {
                let u = Float(k) / Float(n)
                let psi = psi0 + (1 - 2 * u) * (Float.pi - 0.35)
                let radius = 0.95 * pow(sin(.pi * u), 0.35)
                let x = 0.32 * cos(.pi * u)
                let p = V3(x, centre.y + radius * cos(psi) , centre.z + radius * sin(psi))
                let end = k == n ? mirrorX(hand) : p
                props.append(.cable(from: prev, to: end))
                prev = end
            }
            return makeFrame(s, props)
        }
    }

    // MARK: Battle ropes

    static func battleRopes() -> ExerciseGuideMotion {
        var traits = cardioTraits(.leftWrist)
        traits.feetPlanted = true
        return motion("Battle Ropes", id: "battle-ropes", duration: 1.6,
                      phases: [(0, "Left arm up"), (0.5, "Right arm up")],
                      primary: [.frontDelts, .sideDelts], secondary: [.abs, .quads, .glutes, .forearms],
                      camera: .side, focus: 1.0,
                      setup: ["Stand facing the anchor point with feet shoulder-width apart.",
                              "Sink into a quarter squat with a flat back.",
                              "Hold one rope end in each hand."],
                      cues: ["Whip your arms up and down in alternating waves.",
                             "Keep your hips low and your core braced.",
                             "Keep the waves travelling all the way to the anchor."],
                      mistakes: ["Standing upright so your legs stop working.",
                                 "Using only your hands instead of your whole arms.",
                                 "Letting the waves die before they reach the anchor."],
                      traits: traits) { t in
            var s = PoseSpec()
            s.pelvis = V3(0, 0.74 + 0.02 * cos(4 * .pi * t), -0.08)
            s.pelvisPitch = Ease.rad(22)
            s.headPitch = -0.35
            let dir = FigureSolver.footDir(side: 1, toeOutDegrees: 12)
            s.leftLeg = .plant(ankle: V3(0.18, 0.08, 0), pole: V3(0.2, 0.2, 1), footDir: dir)
            s.rightLeg = .plant(ankle: V3(-0.18, 0.08, 0), pole: V3(-0.2, 0.2, 1), footDir: V3(-dir.x, dir.y, dir.z))
            let ang = 2 * .pi * t
            let amp: Float = 0.22
            let hl = V3(0.14, 0.95 + amp * sin(ang), 0.40)
            let hr = V3(-0.14, 0.95 + amp * sin(ang + .pi), 0.40)
            s.leftArm = .reach(hand: hl, pole: V3(0.3, -1, -0.1), handDir: nil)
            s.rightArm = .reach(hand: hr, pole: V3(-0.3, -1, -0.1), handDir: nil)
            var props: [GuideProp] = []
            let anchorZ: Float = 3.0
            for (hand, phase) in [(hl, Float(0)), (hr, Float.pi)] {
                var prev = hand
                let n = 14
                for k in 1...n {
                    let u = Float(k) / Float(n)
                    let z = Ease.lerp(hand.z, anchorZ, u)
                    let base = Ease.lerp(hand.y - amp * sin(ang + phase), 0.35, u)
                    let wave = amp * (1 - 0.75 * u) * sin(ang + phase - 2 * .pi * 1.2 * u)
                    let p = V3(hand.x, base + wave, z)
                    props.append(.cable(from: prev, to: p))
                    prev = p
                }
                props.append(Props.rod(V3(hand.x, 0.25, anchorZ), V3(hand.x, 0.45, anchorZ), 0.04))
            }
            props.append(Props.rod(V3(0.14, 0.40, anchorZ), V3(-0.14, 0.40, anchorZ), 0.04))
            return makeFrame(s, props)
        }
    }

    // MARK: Elliptical

    static func elliptical() -> ExerciseGuideMotion {
        let traits = cardioTraits(.leftAnkle)
        return motion("Elliptical", id: "elliptical", duration: 2.4,
                      phases: [(0, "Left foot forward"), (0.5, "Right foot forward")],
                      primary: [.quads, .glutes], secondary: [.hamstrings, .calves, .lats, .biceps],
                      camera: .side, focus: 0.9,
                      setup: ["Step onto the pedals and hold the moving handles.",
                              "Stand tall with your hips under your shoulders.",
                              "Place your whole foot flat on each pedal."],
                      cues: ["Push and pull the handles in rhythm with your legs.",
                             "Keep your weight over your heels and your torso tall.",
                             "Keep your knees soft and tracking over your toes."],
                      mistakes: ["Leaning on the handles and unloading your legs.",
                                 "Rising onto your toes.",
                                 "Slouching forward over the console."],
                      traits: traits) { t in
            let thL = 2 * .pi * t
            let thR = thL + .pi
            func pedal(_ th: Float) -> V3 { V3(0, 0.26 + 0.05 * cos(th), 0.20 * sin(th)) }
            let pl = pedal(thL), pr = pedal(thR)
            let dir = FigureSolver.footDir(side: 1, toeOutDegrees: 4)
            let off = V3(0, 0.11, -0.09)
            var s = PoseSpec()
            s.pelvis = V3(0, 1.0, 0.0)
            s.pelvisPitch = Ease.rad(3)
            s.leftLeg = .plant(ankle: V3(0.12, 0, 0) + pl + off, pole: V3(0.1, 0.2, 1), footDir: dir)
            s.rightLeg = .plant(ankle: V3(-0.12, 0, 0) + pr + off, pole: V3(-0.1, 0.2, 1), footDir: V3(-dir.x, dir.y, dir.z))
            let hl = V3(0.30, 1.22 + 0.03 * cos(thL), 0.26 - 0.15 * sin(thL))
            let hr = V3(-0.30, 1.22 + 0.03 * cos(thR), 0.26 - 0.15 * sin(thR))
            s.leftArm = .reach(hand: hl, pole: V3(0.4, -1, -0.3), handDir: V3(0, 0, 1))
            s.rightArm = .reach(hand: hr, pole: V3(-0.4, -1, -0.3), handDir: V3(0, 0, 1))
            var props: [GuideProp] = [
                Props.box(V3(0.12, pl.y + 0.005, pl.z), V3(0.20, 0.05, 0.32), identity, .platform),
                Props.box(V3(-0.12, pr.y + 0.005, pr.z), V3(0.20, 0.05, 0.32), identity, .platform),
                Props.rod(V3(0.30, 1.45, 0.50), hl, 0.02),
                Props.rod(V3(-0.30, 1.45, 0.50), hr, 0.02),
                Props.rod(V3(0.30, 0, 0.62), V3(0.30, 1.50, 0.58), 0.035),
                Props.rod(V3(-0.30, 0, 0.62), V3(-0.30, 1.50, 0.58), 0.035)
            ]
            props.append(Props.box(V3(0, 1.55, 0.58), V3(0.50, 0.20, 0.10), identity, .frame))
            props.append(Props.box(V3(0, 0.10, 0.0), V3(0.70, 0.20, 1.10), identity, .frame))
            return makeFrame(s, props)
        }
    }
}
