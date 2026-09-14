import Foundation
import simd

/// Hardcoded reference keyframes for exercise categories.
/// Each keyframe is a dictionary of joint name → normalized position (y=0 floor, y=1 head height).
enum IdealFormData {

    /// Returns keyframes for the given exercise name.
    static func keyframes(for exerciseName: String) -> [[String: simd_float3]] {
        let lower = exerciseName.lowercased()
        if lower.contains("push up") || lower.contains("pushup") || lower.contains("push-up") {
            return pushupKeyframes
        } else if lower.contains("squat") || lower.contains("lunge") {
            return squatKeyframes
        } else if lower.contains("deadlift") || lower.contains("rdl") {
            return deadliftKeyframes
        } else if lower.contains("bench press") || lower.contains("chest press")
                    || lower.contains("incline press") || lower.contains("decline press") {
            return benchPressKeyframes
        } else if lower.contains("row") || lower.contains("pull") || lower.contains("curl") {
            return upperPullKeyframes
        } else {
            return upperPushKeyframes
        }
    }

    /// Returns 3 quick form tips for the given exercise name.
    static func tips(for exerciseName: String) -> [String] {
        let lower = exerciseName.lowercased()
        if lower.contains("push up") || lower.contains("pushup") || lower.contains("push-up") {
            return [
                "Keep your body in a straight line from head to heels",
                "Lower your chest to within an inch of the floor",
                "Squeeze your core and glutes throughout the movement"
            ]
        } else if lower.contains("squat") || lower.contains("lunge") {
            return [
                "Keep your chest tall and knees tracking over your toes",
                "Descend until thighs are at least parallel to the floor",
                "Drive through your heels to stand — don't let knees cave in"
            ]
        } else if lower.contains("deadlift") || lower.contains("rdl") {
            return [
                "Brace your core and keep a neutral spine — no rounding",
                "Bar stays close to your body the entire lift",
                "Hinge at the hips, then push the floor away to lockout"
            ]
        } else if lower.contains("bench press") || lower.contains("chest press") {
            return [
                "Arch your upper back and retract your scapula before unracking",
                "Lower the bar to your lower chest with elbows at ~75°",
                "Drive your feet into the floor to build leg drive"
            ]
        } else if lower.contains("pull up") || lower.contains("chin up") || lower.contains("row") {
            return [
                "Start from a dead hang with fully extended arms",
                "Drive elbows down and back — lead with your chest",
                "Pause at the top and squeeze your lats before descending"
            ]
        } else if lower.contains("curl") {
            return [
                "Keep your elbows pinned at your sides throughout",
                "Fully supinate your wrist at the top of the rep",
                "Control the lowering — take 2–3 seconds to descend"
            ]
        } else {
            return [
                "Control the weight through the full range of motion",
                "Brace your core and maintain a neutral spine",
                "Focus on the muscle — mind-muscle connection matters"
            ]
        }
    }

    // MARK: - Squat (7 keyframes: stand → 1/8-down → quarter-down → bottom → hold → quarter-up → stand)

    static let squatKeyframes: [[String: simd_float3]] = [
        // Frame 0 — Standing
        [
            "neck":          simd_float3(0, 1.5, 0),
            "leftShoulder":  simd_float3(-0.2, 1.4, 0),
            "rightShoulder": simd_float3( 0.2, 1.4, 0),
            "leftHip":       simd_float3(-0.1, 0.9, 0),
            "rightHip":      simd_float3( 0.1, 0.9, 0),
            "leftKnee":      simd_float3(-0.12, 0.45, 0.02),
            "rightKnee":     simd_float3( 0.12, 0.45, 0.02),
            "leftAnkle":     simd_float3(-0.12, 0, 0),
            "rightAnkle":    simd_float3( 0.12, 0, 0),
            "leftElbow":     simd_float3(-0.35, 1.1, 0.15),
            "rightElbow":    simd_float3( 0.35, 1.1, 0.15),
            "leftWrist":     simd_float3(-0.40, 1.0, 0.20),
            "rightWrist":    simd_float3( 0.40, 1.0, 0.20),
        ],
        // Frame 1 — 1/8 descent
        [
            "neck":          simd_float3(0, 1.42, 0),
            "leftShoulder":  simd_float3(-0.2, 1.32, 0),
            "rightShoulder": simd_float3( 0.2, 1.32, 0),
            "leftHip":       simd_float3(-0.11, 0.82, 0),
            "rightHip":      simd_float3( 0.11, 0.82, 0),
            "leftKnee":      simd_float3(-0.135, 0.40, 0.05),
            "rightKnee":     simd_float3( 0.135, 0.40, 0.05),
            "leftAnkle":     simd_float3(-0.125, 0, 0),
            "rightAnkle":    simd_float3( 0.125, 0, 0),
            "leftElbow":     simd_float3(-0.35, 1.05, 0.15),
            "rightElbow":    simd_float3( 0.35, 1.05, 0.15),
            "leftWrist":     simd_float3(-0.40, 0.95, 0.21),
            "rightWrist":    simd_float3( 0.40, 0.95, 0.21),
        ],
        // Frame 2 — Quarter descent
        [
            "neck":          simd_float3(0, 1.35, 0),
            "leftShoulder":  simd_float3(-0.2, 1.25, 0),
            "rightShoulder": simd_float3( 0.2, 1.25, 0),
            "leftHip":       simd_float3(-0.12, 0.75, 0),
            "rightHip":      simd_float3( 0.12, 0.75, 0),
            "leftKnee":      simd_float3(-0.15, 0.35, 0.08),
            "rightKnee":     simd_float3( 0.15, 0.35, 0.08),
            "leftAnkle":     simd_float3(-0.13, 0, 0),
            "rightAnkle":    simd_float3( 0.13, 0, 0),
            "leftElbow":     simd_float3(-0.35, 1.0, 0.15),
            "rightElbow":    simd_float3( 0.35, 1.0, 0.15),
            "leftWrist":     simd_float3(-0.40, 0.90, 0.22),
            "rightWrist":    simd_float3( 0.40, 0.90, 0.22),
        ],
        // Frame 3 — Bottom (parallel)
        [
            "neck":          simd_float3(0, 1.0, 0.1),
            "leftShoulder":  simd_float3(-0.2, 0.9, 0.08),
            "rightShoulder": simd_float3( 0.2, 0.9, 0.08),
            "leftHip":       simd_float3(-0.18, 0.42, 0.05),
            "rightHip":      simd_float3( 0.18, 0.42, 0.05),
            "leftKnee":      simd_float3(-0.2, 0.22, 0.2),
            "rightKnee":     simd_float3( 0.2, 0.22, 0.2),
            "leftAnkle":     simd_float3(-0.17, 0, 0),
            "rightAnkle":    simd_float3( 0.17, 0, 0),
            "leftElbow":     simd_float3(-0.35, 0.75, 0.2),
            "rightElbow":    simd_float3( 0.35, 0.75, 0.2),
            "leftWrist":     simd_float3(-0.38, 0.72, 0.25),
            "rightWrist":    simd_float3( 0.38, 0.72, 0.25),
        ],
        // Frame 4 — Bottom hold (same as frame 3 — pause at depth)
        [
            "neck":          simd_float3(0, 1.0, 0.1),
            "leftShoulder":  simd_float3(-0.2, 0.9, 0.08),
            "rightShoulder": simd_float3( 0.2, 0.9, 0.08),
            "leftHip":       simd_float3(-0.18, 0.42, 0.05),
            "rightHip":      simd_float3( 0.18, 0.42, 0.05),
            "leftKnee":      simd_float3(-0.2, 0.22, 0.2),
            "rightKnee":     simd_float3( 0.2, 0.22, 0.2),
            "leftAnkle":     simd_float3(-0.17, 0, 0),
            "rightAnkle":    simd_float3( 0.17, 0, 0),
            "leftElbow":     simd_float3(-0.35, 0.75, 0.2),
            "rightElbow":    simd_float3( 0.35, 0.75, 0.2),
            "leftWrist":     simd_float3(-0.38, 0.72, 0.25),
            "rightWrist":    simd_float3( 0.38, 0.72, 0.25),
        ],
        // Frame 5 — Quarter ascent (mirror of frame 2)
        [
            "neck":          simd_float3(0, 1.35, 0),
            "leftShoulder":  simd_float3(-0.2, 1.25, 0),
            "rightShoulder": simd_float3( 0.2, 1.25, 0),
            "leftHip":       simd_float3(-0.12, 0.75, 0),
            "rightHip":      simd_float3( 0.12, 0.75, 0),
            "leftKnee":      simd_float3(-0.15, 0.35, 0.08),
            "rightKnee":     simd_float3( 0.15, 0.35, 0.08),
            "leftAnkle":     simd_float3(-0.13, 0, 0),
            "rightAnkle":    simd_float3( 0.13, 0, 0),
            "leftElbow":     simd_float3(-0.35, 1.0, 0.15),
            "rightElbow":    simd_float3( 0.35, 1.0, 0.15),
            "leftWrist":     simd_float3(-0.40, 0.90, 0.22),
            "rightWrist":    simd_float3( 0.40, 0.90, 0.22),
        ],
        // Frame 6 — Standing again (same as frame 0)
        [
            "neck":          simd_float3(0, 1.5, 0),
            "leftShoulder":  simd_float3(-0.2, 1.4, 0),
            "rightShoulder": simd_float3( 0.2, 1.4, 0),
            "leftHip":       simd_float3(-0.1, 0.9, 0),
            "rightHip":      simd_float3( 0.1, 0.9, 0),
            "leftKnee":      simd_float3(-0.12, 0.45, 0.02),
            "rightKnee":     simd_float3( 0.12, 0.45, 0.02),
            "leftAnkle":     simd_float3(-0.12, 0, 0),
            "rightAnkle":    simd_float3( 0.12, 0, 0),
            "leftElbow":     simd_float3(-0.35, 1.1, 0.15),
            "rightElbow":    simd_float3( 0.35, 1.1, 0.15),
            "leftWrist":     simd_float3(-0.40, 1.0, 0.20),
            "rightWrist":    simd_float3( 0.40, 1.0, 0.20),
        ],
    ]

    // MARK: - Push-up (4 keyframes: top → lowering → bottom → return)

    static let pushupKeyframes: [[String: simd_float3]] = [
        // Top — arms extended (plank position)
        [
            "neck":          simd_float3(0,  0.75, 0.05),
            "leftShoulder":  simd_float3(-0.22, 0.70, 0),
            "rightShoulder": simd_float3( 0.22, 0.70, 0),
            "leftHip":       simd_float3(-0.1,  0.45, -0.5),
            "rightHip":      simd_float3( 0.1,  0.45, -0.5),
            "leftKnee":      simd_float3(-0.12, 0.22, -0.9),
            "rightKnee":     simd_float3( 0.12, 0.22, -0.9),
            "leftAnkle":     simd_float3(-0.12, 0.08, -1.3),
            "rightAnkle":    simd_float3( 0.12, 0.08, -1.3),
            "leftElbow":     simd_float3(-0.22, 0.42, 0.28),
            "rightElbow":    simd_float3( 0.22, 0.42, 0.28),
            "leftWrist":     simd_float3(-0.22, 0.10, 0.30),
            "rightWrist":    simd_float3( 0.22, 0.10, 0.30),
        ],
        // Lowering — halfway down
        [
            "neck":          simd_float3(0,  0.58, 0.05),
            "leftShoulder":  simd_float3(-0.22, 0.54, 0),
            "rightShoulder": simd_float3( 0.22, 0.54, 0),
            "leftHip":       simd_float3(-0.1,  0.40, -0.5),
            "rightHip":      simd_float3( 0.1,  0.40, -0.5),
            "leftKnee":      simd_float3(-0.12, 0.22, -0.9),
            "rightKnee":     simd_float3( 0.12, 0.22, -0.9),
            "leftAnkle":     simd_float3(-0.12, 0.08, -1.3),
            "rightAnkle":    simd_float3( 0.12, 0.08, -1.3),
            "leftElbow":     simd_float3(-0.32, 0.50, 0.15),
            "rightElbow":    simd_float3( 0.32, 0.50, 0.15),
            "leftWrist":     simd_float3(-0.22, 0.10, 0.30),
            "rightWrist":    simd_float3( 0.22, 0.10, 0.30),
        ],
        // Bottom — chest near floor, elbows at ~90°
        [
            "neck":          simd_float3(0,  0.38, 0.08),
            "leftShoulder":  simd_float3(-0.22, 0.34, 0),
            "rightShoulder": simd_float3( 0.22, 0.34, 0),
            "leftHip":       simd_float3(-0.1,  0.36, -0.5),
            "rightHip":      simd_float3( 0.1,  0.36, -0.5),
            "leftKnee":      simd_float3(-0.12, 0.22, -0.9),
            "rightKnee":     simd_float3( 0.12, 0.22, -0.9),
            "leftAnkle":     simd_float3(-0.12, 0.08, -1.3),
            "rightAnkle":    simd_float3( 0.12, 0.08, -1.3),
            "leftElbow":     simd_float3(-0.36, 0.34, 0.05),
            "rightElbow":    simd_float3( 0.36, 0.34, 0.05),
            "leftWrist":     simd_float3(-0.22, 0.10, 0.30),
            "rightWrist":    simd_float3( 0.22, 0.10, 0.30),
        ],
        // Return to top (same as frame 0)
        [
            "neck":          simd_float3(0,  0.75, 0.05),
            "leftShoulder":  simd_float3(-0.22, 0.70, 0),
            "rightShoulder": simd_float3( 0.22, 0.70, 0),
            "leftHip":       simd_float3(-0.1,  0.45, -0.5),
            "rightHip":      simd_float3( 0.1,  0.45, -0.5),
            "leftKnee":      simd_float3(-0.12, 0.22, -0.9),
            "rightKnee":     simd_float3( 0.12, 0.22, -0.9),
            "leftAnkle":     simd_float3(-0.12, 0.08, -1.3),
            "rightAnkle":    simd_float3( 0.12, 0.08, -1.3),
            "leftElbow":     simd_float3(-0.22, 0.42, 0.28),
            "rightElbow":    simd_float3( 0.22, 0.42, 0.28),
            "leftWrist":     simd_float3(-0.22, 0.10, 0.30),
            "rightWrist":    simd_float3( 0.22, 0.10, 0.30),
        ],
    ]

    // MARK: - Deadlift (4 keyframes: standing → setup → mid-pull → lockout)

    static let deadliftKeyframes: [[String: simd_float3]] = [
        // Frame 0 — Standing
        [
            "neck":          simd_float3(0, 1.5, 0),
            "leftShoulder":  simd_float3(-0.2, 1.4, 0),
            "rightShoulder": simd_float3( 0.2, 1.4, 0),
            "leftHip":       simd_float3(-0.1, 0.9, 0),
            "rightHip":      simd_float3( 0.1, 0.9, 0),
            "leftKnee":      simd_float3(-0.12, 0.45, 0),
            "rightKnee":     simd_float3( 0.12, 0.45, 0),
            "leftAnkle":     simd_float3(-0.12, 0, 0),
            "rightAnkle":    simd_float3( 0.12, 0, 0),
            "leftElbow":     simd_float3(-0.2, 1.1, 0.1),
            "rightElbow":    simd_float3( 0.2, 1.1, 0.1),
            "leftWrist":     simd_float3(-0.18, 0.75, 0.05),
            "rightWrist":    simd_float3( 0.18, 0.75, 0.05),
        ],
        // Frame 1 — Setup (hips back, bar at shin)
        [
            "neck":          simd_float3(0, 1.1, 0.3),
            "leftShoulder":  simd_float3(-0.22, 1.0, 0.25),
            "rightShoulder": simd_float3( 0.22, 1.0, 0.25),
            "leftHip":       simd_float3(-0.1, 0.85, 0.05),
            "rightHip":      simd_float3( 0.1, 0.85, 0.05),
            "leftKnee":      simd_float3(-0.14, 0.4, 0.1),
            "rightKnee":     simd_float3( 0.14, 0.4, 0.1),
            "leftAnkle":     simd_float3(-0.13, 0, 0),
            "rightAnkle":    simd_float3( 0.13, 0, 0),
            "leftElbow":     simd_float3(-0.22, 0.7, 0.25),
            "rightElbow":    simd_float3( 0.22, 0.7, 0.25),
            "leftWrist":     simd_float3(-0.18, 0.22, 0.12),
            "rightWrist":    simd_float3( 0.18, 0.22, 0.12),
        ],
        // Frame 2 — Mid-pull (bar at knee)
        [
            "neck":          simd_float3(0, 1.25, 0.15),
            "leftShoulder":  simd_float3(-0.22, 1.15, 0.12),
            "rightShoulder": simd_float3( 0.22, 1.15, 0.12),
            "leftHip":       simd_float3(-0.1, 0.88, 0.02),
            "rightHip":      simd_float3( 0.1, 0.88, 0.02),
            "leftKnee":      simd_float3(-0.13, 0.42, 0.05),
            "rightKnee":     simd_float3( 0.13, 0.42, 0.05),
            "leftAnkle":     simd_float3(-0.13, 0, 0),
            "rightAnkle":    simd_float3( 0.13, 0, 0),
            "leftElbow":     simd_float3(-0.22, 0.85, 0.12),
            "rightElbow":    simd_float3( 0.22, 0.85, 0.12),
            "leftWrist":     simd_float3(-0.18, 0.50, 0.08),
            "rightWrist":    simd_float3( 0.18, 0.50, 0.08),
        ],
        // Frame 3 — Lockout (same as frame 0)
        [
            "neck":          simd_float3(0, 1.5, 0),
            "leftShoulder":  simd_float3(-0.2, 1.4, 0),
            "rightShoulder": simd_float3( 0.2, 1.4, 0),
            "leftHip":       simd_float3(-0.1, 0.9, 0),
            "rightHip":      simd_float3( 0.1, 0.9, 0),
            "leftKnee":      simd_float3(-0.12, 0.45, 0),
            "rightKnee":     simd_float3( 0.12, 0.45, 0),
            "leftAnkle":     simd_float3(-0.12, 0, 0),
            "rightAnkle":    simd_float3( 0.12, 0, 0),
            "leftElbow":     simd_float3(-0.2, 1.1, 0.05),
            "rightElbow":    simd_float3( 0.2, 1.1, 0.05),
            "leftWrist":     simd_float3(-0.18, 0.75, 0.02),
            "rightWrist":    simd_float3( 0.18, 0.75, 0.02),
        ],
    ]

    // MARK: - Bench Press (4 keyframes: lockout → descent → bar at chest → lockout)

    static let benchPressKeyframes: [[String: simd_float3]] = [
        // Frame 0 — Lockout (arms extended upward)
        [
            "neck":          simd_float3(0, 0.80, 0.42),
            "leftShoulder":  simd_float3(-0.22, 0.82, 0.12),
            "rightShoulder": simd_float3( 0.22, 0.82, 0.12),
            "leftHip":       simd_float3(-0.10, 0.60, -0.22),
            "rightHip":      simd_float3( 0.10, 0.60, -0.22),
            "leftKnee":      simd_float3(-0.14, 0.52, -0.55),
            "rightKnee":     simd_float3( 0.14, 0.52, -0.55),
            "leftAnkle":     simd_float3(-0.16, 0.44, -0.88),
            "rightAnkle":    simd_float3( 0.16, 0.44, -0.88),
            "leftElbow":     simd_float3(-0.40, 1.05, 0.12),
            "rightElbow":    simd_float3( 0.40, 1.05, 0.12),
            "leftWrist":     simd_float3(-0.24, 1.15, 0.15),
            "rightWrist":    simd_float3( 0.24, 1.15, 0.15),
        ],
        // Frame 1 — Descent (halfway, elbows ~120°)
        [
            "neck":          simd_float3(0, 0.80, 0.42),
            "leftShoulder":  simd_float3(-0.22, 0.82, 0.12),
            "rightShoulder": simd_float3( 0.22, 0.82, 0.12),
            "leftHip":       simd_float3(-0.10, 0.60, -0.22),
            "rightHip":      simd_float3( 0.10, 0.60, -0.22),
            "leftKnee":      simd_float3(-0.14, 0.52, -0.55),
            "rightKnee":     simd_float3( 0.14, 0.52, -0.55),
            "leftAnkle":     simd_float3(-0.16, 0.44, -0.88),
            "rightAnkle":    simd_float3( 0.16, 0.44, -0.88),
            "leftElbow":     simd_float3(-0.44, 0.90, 0.12),
            "rightElbow":    simd_float3( 0.44, 0.90, 0.12),
            "leftWrist":     simd_float3(-0.24, 0.90, 0.15),
            "rightWrist":    simd_float3( 0.24, 0.90, 0.15),
        ],
        // Frame 2 — Bar at lower chest
        [
            "neck":          simd_float3(0, 0.80, 0.42),
            "leftShoulder":  simd_float3(-0.22, 0.82, 0.12),
            "rightShoulder": simd_float3( 0.22, 0.82, 0.12),
            "leftHip":       simd_float3(-0.10, 0.60, -0.22),
            "rightHip":      simd_float3( 0.10, 0.60, -0.22),
            "leftKnee":      simd_float3(-0.14, 0.52, -0.55),
            "rightKnee":     simd_float3( 0.14, 0.52, -0.55),
            "leftAnkle":     simd_float3(-0.16, 0.44, -0.88),
            "rightAnkle":    simd_float3( 0.16, 0.44, -0.88),
            "leftElbow":     simd_float3(-0.46, 0.78, 0.10),
            "rightElbow":    simd_float3( 0.46, 0.78, 0.10),
            "leftWrist":     simd_float3(-0.24, 0.62, 0.15),
            "rightWrist":    simd_float3( 0.24, 0.62, 0.15),
        ],
        // Frame 3 — Lockout again (same as frame 0)
        [
            "neck":          simd_float3(0, 0.80, 0.42),
            "leftShoulder":  simd_float3(-0.22, 0.82, 0.12),
            "rightShoulder": simd_float3( 0.22, 0.82, 0.12),
            "leftHip":       simd_float3(-0.10, 0.60, -0.22),
            "rightHip":      simd_float3( 0.10, 0.60, -0.22),
            "leftKnee":      simd_float3(-0.14, 0.52, -0.55),
            "rightKnee":     simd_float3( 0.14, 0.52, -0.55),
            "leftAnkle":     simd_float3(-0.16, 0.44, -0.88),
            "rightAnkle":    simd_float3( 0.16, 0.44, -0.88),
            "leftElbow":     simd_float3(-0.40, 1.05, 0.12),
            "rightElbow":    simd_float3( 0.40, 1.05, 0.12),
            "leftWrist":     simd_float3(-0.24, 1.15, 0.15),
            "rightWrist":    simd_float3( 0.24, 1.15, 0.15),
        ],
    ]

    // MARK: - Upper Push (OHP / push — 3 keyframes)

    static let upperPushKeyframes: [[String: simd_float3]] = [
        // Arms extended (top of press)
        [
            "neck":          simd_float3(0, 1.5, 0),
            "leftShoulder":  simd_float3(-0.2, 1.4, 0),
            "rightShoulder": simd_float3( 0.2, 1.4, 0),
            "leftHip":       simd_float3(-0.1, 0.9, 0),
            "rightHip":      simd_float3( 0.1, 0.9, 0),
            "leftKnee":      simd_float3(-0.12, 0.45, 0),
            "rightKnee":     simd_float3( 0.12, 0.45, 0),
            "leftAnkle":     simd_float3(-0.12, 0, 0),
            "rightAnkle":    simd_float3( 0.12, 0, 0),
            "leftElbow":     simd_float3(-0.35, 1.55, 0.3),
            "rightElbow":    simd_float3( 0.35, 1.55, 0.3),
            "leftWrist":     simd_float3(-0.25, 1.7, 0.6),
            "rightWrist":    simd_float3( 0.25, 1.7, 0.6),
        ],
        // Arms at 90° (bottom of movement)
        [
            "neck":          simd_float3(0, 1.5, 0),
            "leftShoulder":  simd_float3(-0.2, 1.4, 0),
            "rightShoulder": simd_float3( 0.2, 1.4, 0),
            "leftHip":       simd_float3(-0.1, 0.9, 0),
            "rightHip":      simd_float3( 0.1, 0.9, 0),
            "leftKnee":      simd_float3(-0.12, 0.45, 0),
            "rightKnee":     simd_float3( 0.12, 0.45, 0),
            "leftAnkle":     simd_float3(-0.12, 0, 0),
            "rightAnkle":    simd_float3( 0.12, 0, 0),
            "leftElbow":     simd_float3(-0.38, 1.35, 0.1),
            "rightElbow":    simd_float3( 0.38, 1.35, 0.1),
            "leftWrist":     simd_float3(-0.25, 1.45, 0.1),
            "rightWrist":    simd_float3( 0.25, 1.45, 0.1),
        ],
        // Return to extended (same as frame 0)
        [
            "neck":          simd_float3(0, 1.5, 0),
            "leftShoulder":  simd_float3(-0.2, 1.4, 0),
            "rightShoulder": simd_float3( 0.2, 1.4, 0),
            "leftHip":       simd_float3(-0.1, 0.9, 0),
            "rightHip":      simd_float3( 0.1, 0.9, 0),
            "leftKnee":      simd_float3(-0.12, 0.45, 0),
            "rightKnee":     simd_float3( 0.12, 0.45, 0),
            "leftAnkle":     simd_float3(-0.12, 0, 0),
            "rightAnkle":    simd_float3( 0.12, 0, 0),
            "leftElbow":     simd_float3(-0.35, 1.55, 0.3),
            "rightElbow":    simd_float3( 0.35, 1.55, 0.3),
            "leftWrist":     simd_float3(-0.25, 1.7, 0.6),
            "rightWrist":    simd_float3( 0.25, 1.7, 0.6),
        ],
    ]

    // MARK: - Upper Pull (row / curl / chin-up — 3 keyframes)

    static let upperPullKeyframes: [[String: simd_float3]] = [
        // Arms extended (start of pull)
        [
            "neck":          simd_float3(0, 1.5, 0),
            "leftShoulder":  simd_float3(-0.2, 1.4, 0),
            "rightShoulder": simd_float3( 0.2, 1.4, 0),
            "leftHip":       simd_float3(-0.1, 0.9, 0),
            "rightHip":      simd_float3( 0.1, 0.9, 0),
            "leftKnee":      simd_float3(-0.12, 0.45, 0),
            "rightKnee":     simd_float3( 0.12, 0.45, 0),
            "leftAnkle":     simd_float3(-0.12, 0, 0),
            "rightAnkle":    simd_float3( 0.12, 0, 0),
            "leftElbow":     simd_float3(-0.28, 1.2, 0.2),
            "rightElbow":    simd_float3( 0.28, 1.2, 0.2),
            "leftWrist":     simd_float3(-0.25, 1.0, 0.35),
            "rightWrist":    simd_float3( 0.25, 1.0, 0.35),
        ],
        // Arms contracted (peak of pull)
        [
            "neck":          simd_float3(0, 1.5, 0),
            "leftShoulder":  simd_float3(-0.2, 1.4, 0),
            "rightShoulder": simd_float3( 0.2, 1.4, 0),
            "leftHip":       simd_float3(-0.1, 0.9, 0),
            "rightHip":      simd_float3( 0.1, 0.9, 0),
            "leftKnee":      simd_float3(-0.12, 0.45, 0),
            "rightKnee":     simd_float3( 0.12, 0.45, 0),
            "leftAnkle":     simd_float3(-0.12, 0, 0),
            "rightAnkle":    simd_float3( 0.12, 0, 0),
            "leftElbow":     simd_float3(-0.32, 1.3, -0.1),
            "rightElbow":    simd_float3( 0.32, 1.3, -0.1),
            "leftWrist":     simd_float3(-0.25, 1.42, 0),
            "rightWrist":    simd_float3( 0.25, 1.42, 0),
        ],
        // Return to extended (same as frame 0)
        [
            "neck":          simd_float3(0, 1.5, 0),
            "leftShoulder":  simd_float3(-0.2, 1.4, 0),
            "rightShoulder": simd_float3( 0.2, 1.4, 0),
            "leftHip":       simd_float3(-0.1, 0.9, 0),
            "rightHip":      simd_float3( 0.1, 0.9, 0),
            "leftKnee":      simd_float3(-0.12, 0.45, 0),
            "rightKnee":     simd_float3( 0.12, 0.45, 0),
            "leftAnkle":     simd_float3(-0.12, 0, 0),
            "rightAnkle":    simd_float3( 0.12, 0, 0),
            "leftElbow":     simd_float3(-0.28, 1.2, 0.2),
            "rightElbow":    simd_float3( 0.28, 1.2, 0.2),
            "leftWrist":     simd_float3(-0.25, 1.0, 0.35),
            "rightWrist":    simd_float3( 0.25, 1.0, 0.35),
        ],
    ]
}
