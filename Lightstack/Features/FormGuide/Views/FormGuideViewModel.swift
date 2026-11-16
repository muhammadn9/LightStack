import SwiftUI

extension MuscleGroup {
    /// Human-readable name for chips and accessibility.
    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .frontDelts: return "Front delts"
        case .sideDelts: return "Side delts"
        case .rearDelts: return "Rear delts"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .lats: return "Lats"
        case .traps: return "Traps"
        case .upperBack: return "Upper back"
        case .lowerBack: return "Lower back"
        case .abs: return "Abs"
        case .obliques: return "Obliques"
        case .glutes: return "Glutes"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .calves: return "Calves"
        case .adductors: return "Adductors"
        case .hipFlexors: return "Hip flexors"
        }
    }
}

extension GuideCameraPreset {
    var displayName: String {
        switch self {
        case .front: return "Front"
        case .side: return "Side"
        case .threeQuarter: return "3/4"
        case .back: return "Back"
        }
    }

    var accessibilityName: String {
        switch self {
        case .threeQuarter: return "Three-quarter"
        default: return displayName
        }
    }
}

/// State behind `FormGuideView`: owns the scene controller and mirrors playback state for SwiftUI.
@MainActor
final class FormGuideViewModel: ObservableObject {

    let exerciseName: String
    let motion: ExerciseGuideMotion?
    let controller: GuideSceneController?

    @Published private(set) var progress: Float = 0
    @Published private(set) var isPlaying: Bool
    @Published private(set) var speed: Double = 1
    @Published private(set) var camera: GuideCameraPreset
    @Published private(set) var isolatedMuscle: MuscleGroup?
    @Published private(set) var guide: ExerciseGuide?
    @Published private(set) var startImage: UIImage?
    @Published private(set) var endImage: UIImage?

    /// What the user asked for; the controller is paused separately while the sheet is hidden.
    private var wantsPlaying: Bool

    init(exerciseName: String, startsPlaying: Bool = !UIAccessibility.isReduceMotionEnabled,
         motion: ExerciseGuideMotion? = nil) {
        self.exerciseName = exerciseName
        let resolved = motion ?? ExerciseMotionLibrary.motion(for: exerciseName)
        self.motion = resolved
        self.camera = resolved?.defaultCamera ?? .side
        self.wantsPlaying = startsPlaying
        self.isPlaying = startsPlaying
        if let resolved {
            let c = GuideSceneController(startsPlaying: startsPlaying)
            c.load(motion: resolved, animatedHighlight: false)
            self.controller = c
            c.onProgress = { [weak self] p in
                MainActor.assumeIsolated { self?.progress = p }
            }
        } else {
            self.controller = nil
        }
    }

    var hasMotion: Bool { motion != nil }
    var primaryMuscles: [MuscleGroup] { motion?.primaryMuscles ?? [] }
    var secondaryMuscles: [MuscleGroup] {
        let primary = Set(primaryMuscles)
        return (motion?.secondaryMuscles ?? []).filter { !primary.contains($0) }
    }

    var phaseLabel: String {
        guard let motion else { return "" }
        return Self.phaseLabel(for: progress, phases: motion.phases)
    }

    // MARK: Pure helpers

    /// The phase the figure is in: the last phase at or before `progress`, with a small lead-in.
    static func phaseLabel(for progress: Float, phases: [GuidePhase]) -> String {
        guard let first = phases.first else { return "" }
        var current = first
        for phase in phases.sorted(by: { $0.progress < $1.progress }) where phase.progress <= progress + 0.03 {
            current = phase
        }
        return current.label
    }

    /// Highlight sets for the figure: everything, or only `isolated` (keeping its primary/secondary role).
    static func highlightSets(for motion: ExerciseGuideMotion, isolated: MuscleGroup?)
        -> (primary: Set<MuscleGroup>, secondary: Set<MuscleGroup>) {
        let primary = Set(motion.primaryMuscles)
        let secondary = Set(motion.secondaryMuscles).subtracting(primary)
        guard let isolated else { return (primary, secondary) }
        return (primary.intersection([isolated]), secondary.intersection([isolated]))
    }

    // MARK: Actions

    func togglePlay() {
        wantsPlaying.toggle()
        isPlaying = wantsPlaying
        controller?.isPlaying = wantsPlaying
    }

    /// Scrubbing pauses playback and shows that exact progress.
    func scrub(to value: Float) {
        wantsPlaying = false
        isPlaying = false
        controller?.isPlaying = false
        controller?.setProgress(value)
        progress = min(max(value, 0), 1)
    }

    func toggleSpeed() {
        speed = speed == 1 ? 0.5 : 1
        controller?.speed = speed
    }

    func select(camera preset: GuideCameraPreset) {
        camera = preset
        controller?.setCamera(preset, animated: true)
    }

    /// Tapping a chip isolates that muscle; tapping it again restores all.
    func toggleIsolate(_ muscle: MuscleGroup) {
        guard let motion else { return }
        isolatedMuscle = isolatedMuscle == muscle ? nil : muscle
        let sets = Self.highlightSets(for: motion, isolated: isolatedMuscle)
        controller?.setHighlight(primary: sets.primary, secondary: sets.secondary)
    }

    /// Pauses rendering (sheet hidden / app in background); `resume()` restores the user's choice.
    func suspend() { controller?.isPlaying = false }
    func resume() { controller?.isPlaying = wantsPlaying }

    // MARK: Content

    /// Resolves the text guide and decodes its photos once, off the main actor.
    func loadGuide() async {
        let name = exerciseName
        let loaded = await Task.detached(priority: .userInitiated) { () -> (ExerciseGuide, UIImage?, UIImage?)? in
            guard let guide = ExerciseGuideLibrary.shared.guide(for: name) else { return nil }
            let start = guide.imageFiles.first.flatMap { ExerciseGuideLibrary.image(named: $0) }
            let end = guide.imageFiles.dropFirst().first.flatMap { ExerciseGuideLibrary.image(named: $0) }
            return (guide, start, end)
        }.value
        guard !Task.isCancelled else { return }
        guide = loaded?.0
        startImage = loaded?.1
        endImage = loaded?.2
    }
}
