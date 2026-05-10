import Foundation

/// Runtime feature toggles. Flip to `false` to hide a feature's UI surface
/// without deleting any code. Files under the gated feature stay in the repo
/// and re-enable cleanly when the flag flips back on.
enum FeatureFlags {

    /// Motion-capture form analysis (camera + 3D model overlays).
    /// Disabled while pose estimation accuracy and the capture UX are reworked.
    /// Hides: form-demo and form-capture buttons in ActiveWorkoutView.
    static let formAnalysisEnabled: Bool = false
}
