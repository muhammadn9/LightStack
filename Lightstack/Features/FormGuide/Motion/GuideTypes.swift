import Foundation
import simd

/// Public contract of the 3D Form Guide motion core. Pure Foundation + simd:
/// metres, right-handed, Y up, floor at y = 0. The figure faces +Z by default and its LEFT side is +X.

enum GuideJoint: String, CaseIterable, Codable {
    case pelvis, spineMid, chest, neck, head
    case leftShoulder, leftElbow, leftWrist, leftHand
    case rightShoulder, rightElbow, rightWrist, rightHand
    case leftHip, leftKnee, leftAnkle, leftToe
    case rightHip, rightKnee, rightAnkle, rightToe
}

struct FigurePose: Equatable {
    /// World positions; every joint is always present.
    var joints: [GuideJoint: SIMD3<Float>]
    var pelvisRotation: simd_quatf
    var chestRotation: simd_quatf
    var headRotation: simd_quatf
    /// Unit vector along the handle held in that hand (bar axis / dumbbell axis).
    var leftGripAxis: SIMD3<Float>
    var rightGripAxis: SIMD3<Float>

    func position(_ joint: GuideJoint) -> SIMD3<Float> { joints[joint] ?? .zero }
}

enum MuscleGroup: String, CaseIterable, Codable {
    case chest, frontDelts, sideDelts, rearDelts, biceps, triceps, forearms, lats, traps, upperBack, lowerBack
    case abs, obliques, glutes, quads, hamstrings, calves, adductors, hipFlexors
}

/// Things drawn around the figure. Positions are world space for the given frame.
/// Box sizes are along the box's own (rotated) axes: x = width, y = height/length, z = depth.
enum GuideProp: Equatable {
    case barbell(center: SIMD3<Float>, axis: SIMD3<Float>, length: Float, plateRadius: Float)
    case ezBar(center: SIMD3<Float>, axis: SIMD3<Float>)
    case dumbbell(center: SIMD3<Float>, axis: SIMD3<Float>)
    case kettlebell(center: SIMD3<Float>)
    case cable(from: SIMD3<Float>, to: SIMD3<Float>)
    case handle(center: SIMD3<Float>, axis: SIMD3<Float>, length: Float)
    case box(center: SIMD3<Float>, size: SIMD3<Float>, rotation: simd_quatf, kind: BoxKind)
    case cylinder(from: SIMD3<Float>, to: SIMD3<Float>, radius: Float, kind: BoxKind)
    case mat(center: SIMD3<Float>, size: SIMD2<Float>)

    enum BoxKind: String, Codable { case pad, frame, weightStack, platform }
}

struct GuideFrame: Equatable {
    var pose: FigurePose
    var props: [GuideProp]
}

struct GuidePhase: Equatable {
    let progress: Float
    let label: String
}

enum GuideCameraPreset: String, CaseIterable, Codable { case front, side, threeQuarter, back }

/// Facts about a motion that the sanity tests (and the renderer) can rely on.
struct MotionTraits {
    enum Template: String { case squat, deadlift, benchPress, overheadPress, curl, lateralRaise, pullUp, other }

    var template: Template = .other
    /// Both ankles stay put for the whole rep.
    var feetPlanted = false
    /// Held pose with only a tiny motion.
    var isometric = false
    /// Joint whose path length proves the motion actually moves.
    var drivingJoint: GuideJoint = .leftWrist
    /// Largest allowed per-sample (1/40 rep) joint displacement in metres.
    var maxStep: Float = 0.12
    /// Both hands hold one barbell / EZ bar at a constant grip width.
    var bilateralBar = false
    /// Performed lying or sitting on a bench: pad boxes must be present.
    var onBench = false
    /// The exercise's prop expectation by equipment.
    var minPath: Float = 0.15
}

struct ExerciseGuideMotion: Identifiable {
    let id: String
    let exerciseName: String
    let repDuration: TimeInterval
    let phases: [GuidePhase]
    let primaryMuscles: [MuscleGroup]
    let secondaryMuscles: [MuscleGroup]
    let defaultCamera: GuideCameraPreset
    let focusHeight: Float
    let setupSteps: [String]
    let cues: [String]
    let commonMistakes: [String]
    let traits: MotionTraits
    private let builder: (Float) -> GuideFrame

    init(id: String, exerciseName: String, repDuration: TimeInterval, phases: [GuidePhase],
         primaryMuscles: [MuscleGroup], secondaryMuscles: [MuscleGroup], defaultCamera: GuideCameraPreset,
         focusHeight: Float, setupSteps: [String], cues: [String], commonMistakes: [String],
         traits: MotionTraits, builder: @escaping (Float) -> GuideFrame) {
        self.id = id
        self.exerciseName = exerciseName
        self.repDuration = repDuration
        self.phases = phases
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.defaultCamera = defaultCamera
        self.focusHeight = focusHeight
        self.setupSteps = setupSteps
        self.cues = cues
        self.commonMistakes = commonMistakes
        self.traits = traits
        self.builder = builder
    }

    /// progress 0...1 over ONE full rep (start, end position, back to start). Loops seamlessly: frame(0) == frame(1).
    func frame(at progress: Float) -> GuideFrame {
        builder(min(max(progress, 0), 1))
    }

    /// Returns a copy with a different exercise name and id (used for catalog aliases).
    func renamed(id newID: String, exerciseName newName: String) -> ExerciseGuideMotion {
        ExerciseGuideMotion(id: newID, exerciseName: newName, repDuration: repDuration, phases: phases,
                            primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles,
                            defaultCamera: defaultCamera, focusHeight: focusHeight, setupSteps: setupSteps,
                            cues: cues, commonMistakes: commonMistakes, traits: traits, builder: builder)
    }
}
