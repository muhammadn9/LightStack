import Foundation
import simd

/// Hardcoded reference keyframes for 4 exercise categories.
/// Each keyframe is a dictionary of joint name → normalized position (y=0 floor, y=1 head height).
enum IdealFormData {

    /// Returns keyframes for the given exercise name.
    static func keyframes(for exerciseName: String) -> [[String: simd_float3]] {
        let lower = exerciseName.lowercased()
        if lower.contains("squat") || lower.contains("lunge") {
            return squatKeyframes
        } else if lower.contains("deadlift") || lower.contains("rdl") {
            return deadliftKeyframes
        } else if lower.contains("row") || lower.contains("pull") || lower.contains("curl") {
            return upperPullKeyframes
        } else {
            return upperPushKeyframes
        }
    }

    // MARK: - Squat (5 keyframes: stand → descent → bottom → ascent → stand)

    static let squatKeyframes: [[String: simd_float3]] = [
        // Standing (frame 0)
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
        ],
        // Quarter descent (frame 1)
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
        ],
        // Bottom of squat — parallel (frame 2)
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
        ],
        // Quarter ascent (frame 3 — mirror of frame 1)
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
        ],
        // Standing again (frame 4 — same as frame 0)
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
        ],
    ]

    // MARK: - Deadlift (4 keyframes: standing → setup → mid-pull → lockout)

    static let deadliftKeyframes: [[String: simd_float3]] = [
        // Standing (frame 0)
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
        ],
        // Setup position (frame 1)
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
        ],
        // Mid-pull (frame 2)
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
        ],
        // Lockout (frame 3 — same as frame 0)
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
        ],
    ]

    // MARK: - Upper Push (bench / OHP / push-up) — 3 keyframes

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
        // Return to extended (frame 2 — same as frame 0)
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

    // MARK: - Upper Pull (row / curl / chin-up) — 3 keyframes

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
        // Return to extended (frame 2 — same as frame 0)
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
