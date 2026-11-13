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
        cues: ["Hit the same depth on every rep.", "Control the way down, then drive up.", "Keep your chest up and knees over your toes."])

    static let lunge = MovementProfile(
        id: "lunge", displayName: "Lunge / Split Squat", primary: .knee, secondary: .hip,
        minAmplitudeDegrees: 28, fullRangeDegrees: 80, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout], cameraTip: sideWhole,
        cues: ["Lower until your back knee nearly touches the floor.", "Keep your torso upright.", "Push through the whole front foot."])

    static let hinge = MovementProfile(
        id: "hinge", displayName: "Hinge / Deadlift", primary: .hip, secondary: .knee,
        minAmplitudeDegrees: 26, fullRangeDegrees: 75, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout], cameraTip: sideWhole,
        cues: ["Push your hips back, not down.", "Stand fully tall at the top of every rep.", "Keep the weight close to your legs."])

    static let hipThrust = MovementProfile(
        id: "hipThrust", displayName: "Hip Thrust / Glute Bridge", primary: .hip, secondary: .knee,
        minAmplitudeDegrees: 22, fullRangeDegrees: 65, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout],
        cameraTip: "Prop the phone side-on at hip height, 2 m away, with your shoulders, hips and knees in frame.",
        cues: ["Squeeze your glutes hard at the top.", "Keep your ribs down so your lower back stays neutral.", "Pause for a beat at the top of each rep."])

    static let legPress = MovementProfile(
        id: "legPress", displayName: "Leg Press", primary: .knee, secondary: .hip,
        minAmplitudeDegrees: 30, fullRangeDegrees: 85, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .sideImbalance, .lockout], cameraTip: sideLegs,
        cues: ["Lower to the same depth every rep.", "Keep your hips and lower back on the pad.", "Press without locking your knees hard."])

    static let legExtension = MovementProfile(
        id: "legExtension", displayName: "Leg Extension", primary: .knee, secondary: nil,
        minAmplitudeDegrees: 28, fullRangeDegrees: 80, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout], cameraTip: sideLegs,
        cues: ["Extend fully and squeeze at the top.", "Lower slowly instead of dropping the weight.", "Keep your hips down on the seat."])

    static let legCurl = MovementProfile(
        id: "legCurl", displayName: "Leg Curl", primary: .knee, secondary: nil,
        minAmplitudeDegrees: 28, fullRangeDegrees: 80, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout], cameraTip: sideLegs,
        cues: ["Curl through the full range every rep.", "Lower slowly under control.", "Keep your hips pressed into the pad."])

    static let horizontalPress = MovementProfile(
        id: "horizontalPress", displayName: "Bench / Chest Press", primary: .elbow, secondary: .shoulder,
        minAmplitudeDegrees: 32, fullRangeDegrees: 90, checks: allChecks,
        cameraTip: "Film from the side of the bench at chest height, 2–3 m away, so your arms are in view.",
        cues: ["Lower to the same point on your chest every rep.", "Press all the way to full arm extension.", "Control the bar down, don't bounce it."])

    static let overheadPress = MovementProfile(
        id: "overheadPress", displayName: "Overhead Press", primary: .elbow, secondary: .shoulder,
        minAmplitudeDegrees: 33, fullRangeDegrees: 95, checks: swayChecks, cameraTip: sideArms,
        cues: ["Press until your arms are fully locked out overhead.", "Squeeze your glutes and keep your ribs down.", "Don't lean back to finish the rep."])

    static let dipPushUp = MovementProfile(
        id: "dipPushUp", displayName: "Dip / Push-Up", primary: .elbow, secondary: .shoulder,
        minAmplitudeDegrees: 32, fullRangeDegrees: 90, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout],
        cameraTip: "Prop the phone side-on at hip height, 2–3 m away, with your whole body in frame.",
        cues: ["Go down to the same depth every rep.", "Lock your arms out at the top.", "Keep your body in one straight line."])

    static let row = MovementProfile(
        id: "row", displayName: "Row", primary: .elbow, secondary: .shoulder,
        minAmplitudeDegrees: 28, fullRangeDegrees: 80, checks: swayChecks, cameraTip: sideWhole,
        cues: ["Pull your elbow back toward your hip.", "Keep your torso still instead of heaving the weight.", "Let your arms fully straighten between reps."])

    static let verticalPull = MovementProfile(
        id: "verticalPull", displayName: "Pull-Up / Pulldown", primary: .elbow, secondary: .shoulder,
        minAmplitudeDegrees: 35, fullRangeDegrees: 100, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .sideImbalance, .lockout],
        cameraTip: "Prop the phone facing you at chest height, 2–3 m away, so both arms are visible.",
        cues: ["Start every rep from fully straight arms.", "Pull your chest toward the bar or handle.", "Lower under control, don't drop."])

    static let curl = MovementProfile(
        id: "curl", displayName: "Curl", primary: .elbow, secondary: nil,
        minAmplitudeDegrees: 38, fullRangeDegrees: 110, checks: swayChecks,
        cameraTip: "Prop the phone side-on or facing you at chest height, 2 m away, with your arms and upper body in frame.",
        cues: ["Keep your elbows pinned at your sides.", "Don't swing your body to lift the weight.", "Lower all the way down on every rep."])

    static let tricepsExtension = MovementProfile(
        id: "tricepsExtension", displayName: "Triceps Extension", primary: .elbow, secondary: nil,
        minAmplitudeDegrees: 35, fullRangeDegrees: 100, checks: swayChecks, cameraTip: sideArms,
        cues: ["Keep your upper arms still, only your forearms move.", "Straighten your arms fully at the end.", "Lower slowly to a full stretch."])

    static let lateralRaise = MovementProfile(
        id: "lateralRaise", displayName: "Lateral / Front Raise", primary: .shoulder, secondary: nil,
        minAmplitudeDegrees: 28, fullRangeDegrees: 80, checks: swayChecks, cameraTip: frontArms,
        cues: ["Raise to about shoulder height, no higher.", "Don't swing your body to get the weight up.", "Lower slowly instead of letting it drop."])

    static let flye = MovementProfile(
        id: "flye", displayName: "Flye / Reverse Flye", primary: .shoulder, secondary: nil,
        minAmplitudeDegrees: 25, fullRangeDegrees: 70, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .sideImbalance, .lockout], cameraTip: frontArms,
        cues: ["Keep a soft bend in your elbows throughout.", "Move through the same range every rep.", "Squeeze at the end of the movement."])

    static let crunch = MovementProfile(
        id: "crunch", displayName: "Crunch / Leg Raise", primary: .hip, secondary: nil,
        minAmplitudeDegrees: 22, fullRangeDegrees: 60, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout], cameraTip: sideWhole,
        cues: ["Curl up using your abs, not momentum.", "Return all the way to the start position.", "Breathe out as you crunch."])

    /// Cardio, isometric holds and movements the camera can't measure by joint angle.
    static let untracked = MovementProfile(
        id: "untracked", displayName: "Not tracked", primary: .elbow, secondary: nil,
        minAmplitudeDegrees: 18, fullRangeDegrees: 90, checks: [],
        cameraTip: "Rep tracking isn't available for this exercise.",
        cues: [])

    /// Fallback for names nothing matches: elbow angle with conservative checks.
    static let generic = MovementProfile(
        id: "generic", displayName: "Other exercise", primary: .elbow, secondary: .shoulder,
        minAmplitudeDegrees: 28, fullRangeDegrees: 90, checks: [.rangeConsistency, .tempoControl, .fatigueDrift, .lockout],
        cameraTip: "Prop the phone side-on at chest height, 2–3 m away, with your whole body in frame.",
        cues: ["Keep the range the same on every rep.", "Move with control, no bouncing.", "Return fully to the start between reps."])

    static let all: [MovementProfile] = [
        squat, lunge, hinge, hipThrust, legPress, legExtension, legCurl,
        horizontalPress, overheadPress, dipPushUp, row, verticalPull,
        curl, tricepsExtension, lateralRaise, flye, crunch, untracked
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
