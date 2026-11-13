import Foundation

enum FormCheckKind: String, Codable, CaseIterable {
    case rangeConsistency   // reps cut short vs the lifter's own best reps in the set
    case tempoControl       // lowering phase too fast / rep rushed
    case fatigueDrift       // range shrinking across the set
    case sideImbalance      // left vs right differ (only when both sides tracked)
    case torsoSway          // torso swinging = momentum; strict standing/seated isolation lifts
    case lockout            // not reaching full extension/rest position between reps
}

struct MovementProfile: Equatable {
    let id: String
    let displayName: String
    let primary: JointAngle
    let secondary: JointAngle?
    let minAmplitudeDegrees: Double
    let fullRangeDegrees: Double
    let checks: Set<FormCheckKind>
    let cameraTip: String
    let cues: [String]
    /// 4-6 things only eyes can judge on this movement (alignment, bar path, bracing). Given to the AI coach.
    let visualChecks: [String]
    /// Limb whose end joint is tracked relative to its root as the second rep signal; nil = angle only.
    var displacementLimb: DisplacementLimb?
    /// Order in which the signals are preferred when they score equally. The regularity pick decides first.
    var signalOrder: [SignalKind] = [.angle, .displacement]
    /// Torso swing (degrees, peak to peak within a rep) that counts as minor / major momentum.
    var swayMinorDegrees: Double = 12
    var swayMajorDegrees: Double = 20

    /// Joint angles that must be visible for this movement to be tracked.
    var requiredJoints: [JointAngle] { [primary] }

    var isTracked: Bool { id != "untracked" }
}

enum MovementProfileLibrary {

    // MARK: Camera tips

    private static let sideWhole = "Prop the phone side-on at hip height, 2–3 m away, with your whole body in frame."
    private static let sideLegs = "Prop the phone side-on at knee height, 2–3 m away, with your hips, knees and feet in frame."
    private static let frontArms = "Prop the phone facing you at chest height, 2–3 m away, with both arms and hips in frame."
    private static let sideArms = "Prop the phone side-on at chest height, 2–3 m away, with your whole arm and torso in frame."

    private static let allChecks: Set<FormCheckKind> = [.rangeConsistency, .tempoControl, .fatigueDrift, .sideImbalance, .lockout]
    private static let swayChecks: Set<FormCheckKind> = allChecks.union([.torsoSway])

    // MARK: Profiles

    static let squat = MovementProfile(
        id: "squat", displayName: "Squat", primary: .knee, secondary: .hip,
        minAmplitudeDegrees: 30, fullRangeDegrees: 85, checks: allChecks, cameraTip: sideWhole,
        cues: ["Hit the same depth on every rep.", "Control the way down, then drive up.", "Keep your chest up and knees over your toes."],
        visualChecks: ["Knees tracking in line with the toes, not caving inward", "Heels staying flat on the floor", "Depth: hip crease reaching knee height or lower, the same on every rep", "Lower back staying flat, with no rounding or tucking under at the bottom", "Bar or weight staying over the middle of the foot", "Chest up and head neutral"],
        displacementLimb: .leg)

    static let lunge = MovementProfile(
        id: "lunge", displayName: "Lunge / Split Squat", primary: .knee, secondary: .hip,
        minAmplitudeDegrees: 28, fullRangeDegrees: 80, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout], cameraTip: sideWhole,
        cues: ["Lower until your back knee nearly touches the floor.", "Keep your torso upright.", "Push through the whole front foot."],
        visualChecks: ["Front knee tracking over the middle of the foot, not caving in", "Torso upright instead of folding forward", "Front heel staying down", "Back knee lowering toward the floor to a consistent depth", "Hips level and balance steady, with no wobbling"],
        displacementLimb: .leg)

    static let hinge = MovementProfile(
        id: "hinge", displayName: "Hinge / Deadlift", primary: .hip, secondary: .knee,
        minAmplitudeDegrees: 26, fullRangeDegrees: 75, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout], cameraTip: sideWhole,
        cues: ["Push your hips back, not down.", "Finish every rep fully tall with your hips extended.", "Keep the weight close to your legs."],
        visualChecks: ["Lower back staying flat, with no rounding at the bottom", "Weight or bar travelling close to the legs", "Hips pushing back while the shins stay close to vertical", "Shoulders set and neck neutral, head not craning up", "Finishing tall with hips fully extended, not leaning back"],
        displacementLimb: .trunk)

    static let hipThrust = MovementProfile(
        id: "hipThrust", displayName: "Hip Thrust / Glute Bridge", primary: .hip, secondary: .knee,
        minAmplitudeDegrees: 22, fullRangeDegrees: 65, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout],
        cameraTip: "Prop the phone side-on at hip height, 2 m away, with your shoulders, hips and knees in frame.",
        cues: ["Squeeze your glutes hard at the top.", "Keep your ribs down so your lower back stays neutral.", "Pause for a beat at the top of each rep."],
        visualChecks: ["Ribs down and lower back not over-arched at the top", "Hips fully extended so shoulder, hip and knee line up at the top", "Shins roughly vertical and feet flat at the top", "Chin tucked and head neutral", "Knees staying in line with the toes, not caving"],
        displacementLimb: .trunk)

    static let legPress = MovementProfile(
        id: "legPress", displayName: "Leg Press", primary: .knee, secondary: .hip,
        minAmplitudeDegrees: 30, fullRangeDegrees: 85, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .sideImbalance, .lockout], cameraTip: sideLegs,
        cues: ["Lower to the same depth every rep.", "Keep your hips and lower back on the pad.", "Press without locking your knees hard."],
        visualChecks: ["Lower back and hips staying flat on the pad, with no tucking under at the bottom", "Knees tracking over the toes, not caving in", "Whole foot staying flat on the platform", "Knees not snapping into a hard lockout", "Same depth on every rep"],
        displacementLimb: .leg)

    static let legExtension = MovementProfile(
        id: "legExtension", displayName: "Leg Extension", primary: .knee, secondary: nil,
        minAmplitudeDegrees: 28, fullRangeDegrees: 80, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout], cameraTip: sideLegs,
        cues: ["Extend fully and squeeze at the top.", "Lower slowly instead of dropping the weight.", "Keep your hips down on the seat."],
        visualChecks: ["Hips staying down on the seat, not lifting", "Back staying against the pad", "Weight lifted smoothly, not swung up with momentum", "Full extension at the top with a visible squeeze", "Weight lowered under control, not dropped"],
        displacementLimb: .leg)

    static let legCurl = MovementProfile(
        id: "legCurl", displayName: "Leg Curl", primary: .knee, secondary: nil,
        minAmplitudeDegrees: 28, fullRangeDegrees: 80, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout], cameraTip: sideLegs,
        cues: ["Curl through the full range every rep.", "Lower slowly under control.", "Keep your hips pressed into the pad."],
        visualChecks: ["Hips staying pressed into the pad, not lifting", "Weight curled smoothly, not swung with momentum", "Full range at the top of the curl", "Lower back not arching", "Weight lowered under control"],
        displacementLimb: .leg)

    static let horizontalPress = MovementProfile(
        id: "horizontalPress", displayName: "Bench / Chest Press", primary: .elbow, secondary: .shoulder,
        minAmplitudeDegrees: 32, fullRangeDegrees: 90, checks: allChecks,
        cameraTip: "Film from the side of the bench at chest height, 2–3 m away, so your arms are in view.",
        cues: ["Lower to the same point on your chest every rep.", "Press all the way to full arm extension.", "Control the bar down, don't bounce it."],
        visualChecks: ["Forearms vertical under the bar at the bottom", "Elbows tucked at roughly 45 to 70 degrees from the torso, not flared wide", "Wrists stacked over the elbows, not bent back", "Bar touching the same spot on the chest each rep", "Shoulder blades staying pinched back and hips staying on the bench", "Bar path smooth, not drifting toward the face or hips"],
        displacementLimb: .arm)

    static let overheadPress = MovementProfile(
        id: "overheadPress", displayName: "Overhead Press", primary: .elbow, secondary: .shoulder,
        minAmplitudeDegrees: 33, fullRangeDegrees: 95, checks: swayChecks, cameraTip: sideArms,
        cues: ["Press until your arms are fully locked out overhead.", "Squeeze your glutes and keep your ribs down.", "Don't lean back to finish the rep."],
        visualChecks: ["Forearms vertical under the weight", "Lower back not over-arching and ribs not flaring", "Bar path close to the face, with the head moving through at lockout", "Wrists stacked over the elbows", "Shoulders not shrugging to the ears at lockout"],
        displacementLimb: .arm)

    static let dipPushUp = MovementProfile(
        id: "dipPushUp", displayName: "Dip / Push-Up", primary: .elbow, secondary: .shoulder,
        minAmplitudeDegrees: 32, fullRangeDegrees: 90, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout],
        cameraTip: "Prop the phone side-on at hip height, 2–3 m away, with your whole body in frame.",
        cues: ["Go down to the same depth every rep.", "Lock your arms out at the top.", "Keep your body in one straight line."],
        visualChecks: ["Body in one straight line, with no sagging hips or piked hips", "Elbows tucked rather than flaring wide", "Reaching the same depth on every rep", "Shoulders not shrugging toward the ears", "Head neutral, not dropping forward"],
        displacementLimb: .arm)

    static let row = MovementProfile(
        id: "row", displayName: "Row", primary: .elbow, secondary: .shoulder,
        minAmplitudeDegrees: 28, fullRangeDegrees: 80, checks: swayChecks, cameraTip: sideWhole,
        cues: ["Pull your elbow back toward your hip.", "Keep your torso still instead of heaving the weight.", "Let your arms fully straighten between reps."],
        visualChecks: ["Shoulder blades pulled back at the finish rather than shrugging up", "Elbow path close to the ribs rather than flared out", "Wrist straight, not bent back", "Lower back rounding at the stretch", "Head position neutral", "Torso rocking back and forth to move the weight"],
        displacementLimb: .arm,
        swayMinorDegrees: 25,
        swayMajorDegrees: 38)

    static let verticalPull = MovementProfile(
        id: "verticalPull", displayName: "Pull-Up / Pulldown", primary: .elbow, secondary: .shoulder,
        minAmplitudeDegrees: 35, fullRangeDegrees: 100, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .sideImbalance, .lockout],
        cameraTip: "Prop the phone facing you at chest height, 2–3 m away, so both arms are visible.",
        cues: ["Start every rep from fully straight arms.", "Pull your chest toward the bar or handle.", "Lower under control, don't drop."],
        visualChecks: ["Shoulders pulling down and back rather than shrugging up", "Legs or body swinging to get the weight moving", "Elbows travelling down beside the torso", "Arms fully straight at the start of each rep", "Chest reaching the bar or handle at the end of the pull"],
        displacementLimb: .arm)

    static let curl = MovementProfile(
        id: "curl", displayName: "Curl", primary: .elbow, secondary: nil,
        minAmplitudeDegrees: 38, fullRangeDegrees: 110, checks: swayChecks,
        cameraTip: "Prop the phone side-on or facing you at chest height, 2 m away, with your arms and upper body in frame.",
        cues: ["Keep your elbows pinned at your sides.", "Don't swing your body to lift the weight.", "Lower all the way down on every rep."],
        visualChecks: ["Elbows staying pinned at the sides, not drifting forward", "Wrists straight, not curled or bent", "Shoulders not shrugging or rocking forward", "Arms fully straight at the bottom of each rep", "Torso not leaning back to finish the rep"],
        displacementLimb: .arm)

    static let tricepsExtension = MovementProfile(
        id: "tricepsExtension", displayName: "Triceps Extension", primary: .elbow, secondary: nil,
        minAmplitudeDegrees: 35, fullRangeDegrees: 100, checks: swayChecks, cameraTip: sideArms,
        cues: ["Keep your upper arms still, only your forearms move.", "Straighten your arms fully at the end.", "Lower slowly to a full stretch."],
        visualChecks: ["Upper arms staying still, with the elbows not flaring or drifting", "Elbows pointing the same direction on every rep", "Wrists straight, not bent", "Arms fully straight at the end of each rep", "Lower back not arching and head not jutting forward", "Shoulders not shrugging"],
        displacementLimb: .arm)

    static let lateralRaise = MovementProfile(
        id: "lateralRaise", displayName: "Lateral / Front Raise", primary: .shoulder, secondary: nil,
        minAmplitudeDegrees: 28, fullRangeDegrees: 80, checks: swayChecks, cameraTip: frontArms,
        cues: ["Raise to about shoulder height, no higher.", "Don't swing your body to get the weight up.", "Lower slowly instead of letting it drop."],
        visualChecks: ["Arm path staying at or below shoulder height", "Shoulders not shrugging up toward the ears", "Elbow slightly bent and leading, rather than the wrist leading", "Torso leaning or swinging to start the lift", "Arm sweeping out or forward in the same line each rep"],
        displacementLimb: .arm,
        signalOrder: [.displacement, .angle])

    static let flye = MovementProfile(
        id: "flye", displayName: "Flye / Reverse Flye", primary: .shoulder, secondary: nil,
        minAmplitudeDegrees: 25, fullRangeDegrees: 70, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .sideImbalance, .lockout], cameraTip: frontArms,
        cues: ["Keep a soft bend in your elbows throughout.", "Move through the same range every rep.", "Squeeze at the end of the movement."],
        visualChecks: ["Arm path staying in one plane, at shoulder height for rear delt work", "Elbow keeping the same soft bend throughout, not bending and straightening", "Shoulders not shrugging up", "Torso rotating or leaning to cheat the movement", "Wrist straight, not bent"],
        displacementLimb: .arm,
        signalOrder: [.displacement, .angle])

    static let crunch = MovementProfile(
        id: "crunch", displayName: "Crunch / Leg Raise", primary: .hip, secondary: nil,
        minAmplitudeDegrees: 22, fullRangeDegrees: 60, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout], cameraTip: sideWhole,
        cues: ["Curl up using your abs, not momentum.", "Return all the way to the start position.", "Breathe out as you crunch."],
        visualChecks: ["Neck not being pulled forward by the hands, chin not jammed to the chest", "Ribs curling toward the hips rather than just the head lifting", "Legs or body not swinging to create momentum", "Lower back staying controlled, not arching off the floor or the bench on leg raises", "Full range with a controlled return"],
        displacementLimb: .trunk)

    static let hipAbduction = MovementProfile(
        id: "hipAbduction", displayName: "Hip Abduction / Adduction", primary: .hip, secondary: nil,
        minAmplitudeDegrees: 18, fullRangeDegrees: 50, checks: allChecks,
        cameraTip: "Prop the phone facing you at hip height, 2–3 m away, with both legs and your hips in frame.",
        cues: ["Move the leg out and back in the same line every rep.", "Keep your standing leg steady.", "Control the leg on the way back instead of letting it drop."],
        visualChecks: ["Torso leaning away from the working leg to gain range", "Toes and knee of the working leg pointing forward, not rotated up", "Hips staying level, with no hiking on the working side", "Standing knee staying soft and steady", "Leg swinging with momentum instead of moving smoothly"],
        displacementLimb: .leg, signalOrder: [.displacement, .angle])

    /// Cardio, isometric holds and movements the camera can't measure by joint angle.
    static let untracked = MovementProfile(
        id: "untracked", displayName: "Not tracked", primary: .elbow, secondary: nil,
        minAmplitudeDegrees: 18, fullRangeDegrees: 90, checks: [],
        cameraTip: "Rep tracking isn't available for this exercise.",
        cues: [],
        visualChecks: ["Overall posture and alignment", "Joint alignment through the movement", "Controlled speed", "Same movement pattern on every rep"])

    /// Fallback for names nothing matches: elbow angle with conservative checks.
    static let generic = MovementProfile(
        id: "generic", displayName: "Other exercise", primary: .elbow, secondary: .shoulder,
        minAmplitudeDegrees: 28, fullRangeDegrees: 90, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout],
        cameraTip: "Prop the phone side-on at chest height, 2–3 m away, with your whole body in frame.",
        cues: ["Keep the range the same on every rep.", "Move with control, no bouncing.", "Return fully to the start between reps."],
        visualChecks: ["Joints staying aligned through the movement", "Torso staying steady", "Range of motion matching on every rep", "Controlled speed with no bouncing or swinging"],
        displacementLimb: .arm)

    static let all: [MovementProfile] = [
        squat, lunge, hinge, hipThrust, legPress, legExtension, legCurl,
        horizontalPress, overheadPress, dipPushUp, row, verticalPull,
        curl, tricepsExtension, lateralRaise, flye, crunch, hipAbduction, untracked
    ]

    // MARK: Lookup

    /// Exact catalog match first, then ExerciseNameResolver, then keyword rules.
    /// Never returns nil; returns `generic` only for names nothing matches.
    static func profile(for exerciseName: String) -> MovementProfile {
        let key = normalize(exerciseName)
        guard !key.isEmpty else { return generic }

        if let hit = catalogProfiles[key] { return hit }

        var best: (MovementProfile, Double)?
        for (catalogName, profile) in catalogProfiles {
            let score = ExerciseNameResolver.similarity(key, catalogName)
            if score >= ExerciseNameResolver.threshold, score > (best?.1 ?? 0) {
                best = (profile, score)
            }
        }
        if let best { return best.0 }

        return keywordProfile(key) ?? generic
    }

    /// Normalized catalog names mapped to profiles (built with the keyword rules).
    private static let catalogProfiles: [String: MovementProfile] = {
        var map: [String: MovementProfile] = [:]
        for exercise in ExerciseCatalog.exercises {
            let key = normalize(exercise.name)
            if let p = keywordProfile(key) { map[key] = p }
        }
        return map
    }()

    private static func normalize(_ name: String) -> String {
        let lowered = name.lowercased()
        let cleaned = lowered.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    private static func keywordProfile(_ key: String) -> MovementProfile? {
        let n = " " + key + " "
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }

        // Cardio, isometrics, and movements without a trackable joint angle.
        if has("plank", "treadmill", "rowing", "stairmaster", "stair master", "stair climb", "cycling", " bike ", "jump rope",
               "skipping", "battle rope", "elliptical", " run ", "running", "jogging", "sprint", "swim",
               "calf", "shrug", "twist", "woodchop", "wood chop", "carry", "farmer", "burpee", " hold ") { return untracked }

        if has("hip abduction", "hip adduction", "abductor", "adductor", " abduction", " adduction", "glute kickback",
               "donkey kick", "fire hydrant", "leg abduction") { return hipAbduction }
        if has("hip thrust", "glute bridge", "bridge") { return hipThrust }
        if has("leg press") { return legPress }
        if has("leg extension", "knee extension") { return legExtension }
        if has("leg curl", "hamstring curl", "nordic") { return legCurl }
        if has("split squat", "lunge", "step up") { return lunge }
        if has("squat") { return squat }
        if has("deadlift", " rdl ", "good morning", "hyperextension", "back extension", "pull through", "kettlebell swing", " swing ") { return hinge }
        if has("crunch", "sit up", "situp", "leg raise", "knee raise", "ab wheel", "rollout", "toe to bar") { return crunch }
        if has("reverse fly", "reverse flye", "rear delt", "pec deck", "pec dec", " fly ", " flys ", " flye ", " flyes ", " flies ", "crossover", "cable cross") { return flye }
        if has("lateral raise", "side raise", "front raise", "lat raise", " raise ", " raises ") { return lateralRaise }
        if has(" dip ", " dips ", "push up", "pushup", "press up") { return dipPushUp }
        if has("tricep", "skull", "pushdown", "push down", "kickback", "french press", "jm press") { return tricepsExtension }
        if has("curl") { return curl }
        if has("face pull", "upright row", " row ", " rows ") { return row }
        if has("pull up", "pullup", "chin up", "chinup", "pulldown", "pull down", "lat pull", "muscle up") { return verticalPull }
        if has("overhead", "shoulder press", "military", "arnold", " ohp ", "push press") { return overheadPress }
        if has("bench", "chest press", "floor press", " press ", " presses ", "incline", "decline") { return horizontalPress }
        return nil
    }
}
