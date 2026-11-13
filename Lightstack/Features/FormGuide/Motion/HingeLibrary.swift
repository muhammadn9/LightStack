import Foundation
import simd

/// Deadlift, Romanian deadlift and good morning: the hip-hinge family.
enum HingeLibrary {

    static func all() -> [ExerciseGuideMotion] {
        [deadlift(), romanianDeadlift(), goodMorning()]
    }

    static func deadlift() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.template = .deadlift
        traits.feetPlanted = true
        traits.bilateralBar = true
        traits.drivingJoint = .pelvis
        return motion("Deadlift", id: "deadlift", duration: 4.6,
                      phases: [(0, "Bar on floor"), (0.5, "Lockout")],
                      primary: [.lowerBack, .glutes, .hamstrings], secondary: [.quads, .traps, .lats, .forearms],
                      camera: .side, focus: 0.8,
                      setup: ["Stand with the bar over your mid-foot and feet hip-width apart.",
                              "Hinge down and grip the bar just outside your knees.",
                              "Pull your chest up, tighten your lats and flatten your back."],
                      cues: ["Push the floor away while keeping the bar against your legs.",
                             "Keep your back flat from hips to head the whole way.",
                             "Finish tall by squeezing your glutes, without leaning back."],
                      mistakes: ["Rounding your lower back off the floor.",
                                 "Letting the bar drift away from your legs.",
                                 "Leaning back at the top."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.12)
            let ds = d
            let theta0 = Ease.rad(61)
            let theta = theta0 * (1 - Ease.smooth((ds - 0.30) / 0.70))
            let barZ = Ease.lerp(0.08, 0.185, Ease.smooth(ds / 0.30))
            let yp = Ease.lerp(0.62, 0.92, pow(ds, 1.2))
            let chestZ = barZ + Ease.lerp(0.02, -0.11, ds)
            var s = PoseSpec.standing(stance: 0.12, pelvisY: yp, pelvisZ: chestZ - 0.5 * sin(theta))
            s.pelvisPitch = theta
            s.headPitch = -0.10
            let base = FigureSolver.solve(s)
            let yb = Rigs.hangBarY(shoulder: base.position(.leftShoulder), barZ: barZ, halfGrip: 0.235)
            let bar = V3(0, yb, barZ)
            s.gripBar(center: bar, halfGrip: 0.235, handDir: V3(0, -1, 0), pole: V3(0.5, -0.2, -1))
            return makeFrame(s, [Props.barbell(bar)])
        }
    }

    static func romanianDeadlift() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.bilateralBar = true
        traits.drivingJoint = .pelvis
        return motion("Romanian Deadlift", id: "romanian-deadlift", duration: 4.6,
                      phases: [(0, "Standing tall"), (0.5, "Hips back, bar at shins")],
                      primary: [.hamstrings, .glutes], secondary: [.lowerBack, .forearms, .traps],
                      camera: .side, focus: 0.8,
                      setup: ["Stand tall holding the bar at your thighs with an overhand grip.",
                              "Set your feet hip-width apart and unlock your knees slightly.",
                              "Pull your shoulders back and brace your abs."],
                      cues: ["Push your hips straight back and slide the bar down your legs.",
                             "Keep your back flat and your knees softly bent.",
                             "Stop when you feel a deep hamstring stretch, then drive your hips forward."],
                      mistakes: ["Rounding your back to reach lower.",
                                 "Bending your knees into a squat.",
                                 "Letting the bar swing away from your legs."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            let theta = Ease.rad(66) * d
            let barZ = Ease.lerp(0.14, 0.12, d)
            let pz = Ease.lerp(0.03, -0.26, d)
            let py = Ease.lerp(0.92, 0.84, d)
            var s = PoseSpec.standing(stance: 0.12, pelvisY: py, pelvisZ: pz)
            s.pelvisPitch = theta
            s.headPitch = -0.10
            let base = FigureSolver.solve(s)
            let yb = Rigs.hangBarY(shoulder: base.position(.leftShoulder), barZ: barZ, halfGrip: 0.235)
            let bar = V3(0, yb, barZ)
            s.gripBar(center: bar, halfGrip: 0.235, handDir: V3(0, -1, 0), pole: V3(0.5, -0.2, -1))
            return makeFrame(s, [Props.barbell(bar)])
        }
    }

    static func goodMorning() -> ExerciseGuideMotion {
        var traits = MotionTraits()
        traits.feetPlanted = true
        traits.bilateralBar = true
        traits.drivingJoint = .chest
        return motion("Good Morning", id: "good-morning", duration: 4.6,
                      phases: [(0, "Standing tall"), (0.5, "Torso hinged forward")],
                      primary: [.hamstrings, .lowerBack, .glutes], secondary: [.abs],
                      camera: .side, focus: 0.9,
                      setup: ["Set the bar across your upper back like a high-bar squat.",
                              "Stand with feet shoulder-width apart and knees slightly bent.",
                              "Brace your abs and keep your chest up."],
                      cues: ["Push your hips back and let your torso tip forward.",
                             "Keep your back flat and knees softly bent.",
                             "Drive your hips forward to stand tall."],
                      mistakes: ["Rounding your back as you lean forward.",
                                 "Turning it into a squat by bending your knees.",
                                 "Going heavy before the hinge feels natural."],
                      traits: traits) { t in
            let d = Ease.profile(t, hold: 0.10)
            let theta = Ease.rad(68) * d
            var s = PoseSpec.standing(stance: 0.13, pelvisY: Ease.lerp(0.92, 0.84, d), pelvisZ: Ease.lerp(0.02, -0.28, d))
            s.pelvisPitch = theta
            s.headPitch = -theta * 0.5
            let bar = Rigs.holdBackBar(&s)
            return makeFrame(s, [Props.barbell(bar)])
        }
    }
}
