import Foundation

/// Runtime feature toggles. Flip to `false` to hide a feature's UI surface
/// without deleting any code. Files under the gated feature stay in the repo
/// and re-enable cleanly when the flag flips back on.
enum FeatureFlags {

    /// Motion-capture form analysis (camera + 3D model overlays).
    /// Re-enabled after capture/overlay fixes (permission observation, rep index
    /// alignment, aspect-fill skeleton math, capture countdown) — pending
    /// on-device validation. Gates: form-demo and form-capture buttons in
    /// ActiveWorkoutView.
    static let formAnalysisEnabled: Bool = true
}
