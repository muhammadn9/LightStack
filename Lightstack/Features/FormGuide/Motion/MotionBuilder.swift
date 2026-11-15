import Foundation
import simd

/// Authoring wrapper: builds an `ExerciseGuideMotion` from a name, text and a frame closure.
func motion(_ name: String, id: String, duration: TimeInterval = 4,
            phases: [(Float, String)], primary: [MuscleGroup], secondary: [MuscleGroup] = [],
            camera: GuideCameraPreset = .side, focus: Float = 0.9,
            setup: [String], cues: [String], mistakes: [String],
            traits: MotionTraits = MotionTraits(),
            build: @escaping (Float) -> GuideFrame) -> ExerciseGuideMotion {
    ExerciseGuideMotion(
        id: id, exerciseName: name, repDuration: duration,
        phases: phases.map { GuidePhase(progress: $0.0, label: $0.1) },
        primaryMuscles: primary, secondaryMuscles: secondary,
        defaultCamera: camera, focusHeight: focus,
        setupSteps: setup, cues: cues, commonMistakes: mistakes,
        traits: traits, builder: build)
}

/// Shorthand for a frame from a spec plus props.
func makeFrame(_ spec: PoseSpec, _ props: [GuideProp]) -> GuideFrame {
    GuideFrame(pose: FigureSolver.solve(spec), props: props)
}

/// Text-only description of a motion: key heights and joint angles at four progress values.
enum GuideMotionDebug {
    static func describe(_ motion: ExerciseGuideMotion) -> String {
        var lines = ["\(motion.exerciseName) [\(motion.id)] \(motion.repDuration)s"]
        for p in [Float(0), 0.25, 0.5, 0.75] {
            let f = motion.frame(at: p)
            let pose = f.pose
            func y(_ j: GuideJoint) -> String { String(format: "%.2f", pose.position(j).y) }
            func ang(_ a: GuideJoint, _ m: GuideJoint, _ c: GuideJoint) -> String {
                let u = pose.position(a) - pose.position(m)
                let w = pose.position(c) - pose.position(m)
                let lu = simd_length(u), lw = simd_length(w)
                guard lu > 1e-6, lw > 1e-6 else { return "0" }
                return String(format: "%.0f", acos(max(-1, min(1, simd_dot(u, w) / (lu * lw)))) * 180 / .pi)
            }
            let trunk = pose.position(.chest) - pose.position(.pelvis)
            let lean = acos(max(-1, min(1, trunk.y / max(simd_length(trunk), 1e-6)))) * 180 / .pi
            var s = String(format: "  p=%.2f pelvisY=%@ chestY=%@ handsY=%@/%@ trunkLeanFromVertical=%.0f", p,
                           y(.pelvis), y(.chest), y(.leftHand), y(.rightHand), lean)
            s += " elbowL=\(ang(.leftShoulder, .leftElbow, .leftWrist)) elbowR=\(ang(.rightShoulder, .rightElbow, .rightWrist))"
            s += " kneeL=\(ang(.leftHip, .leftKnee, .leftAnkle)) kneeR=\(ang(.rightHip, .rightKnee, .rightAnkle))"
            s += " hipL=\(ang(.chest, .leftHip, .leftKnee)) kneeY=\(y(.leftKnee)) ankleY=\(y(.leftAnkle))"
            s += String(format: " handL=(%.2f,%.2f,%.2f)", pose.position(.leftHand).x, pose.position(.leftHand).y, pose.position(.leftHand).z)
            s += String(format: " pelvisZ=%.2f chestZ=%.2f", pose.position(.pelvis).z, pose.position(.chest).z)
            lines.append(s)
        }
        return lines.joined(separator: "\n")
    }
}
