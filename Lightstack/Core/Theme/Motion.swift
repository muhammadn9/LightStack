import SwiftUI

/// Shared animation curves. Physics-based springs rather than fixed-duration
/// easing, so interrupted gestures retarget smoothly instead of snapping.
enum AppMotion {

    /// Card expand / collapse. Settles quickly with a trace of overshoot.
    static let cardExpand = Animation.spring(response: 0.38, dampingFraction: 0.78)

    /// Tab indicator slide. Slightly faster and flatter than `cardExpand`.
    static let tabSwitch = Animation.spring(response: 0.32, dampingFraction: 0.82)

    /// Press-down feedback. Short and critically damped — no bounce.
    static let press = Animation.spring(response: 0.22, dampingFraction: 1.0)

    /// Phase / screen cross-fade.
    static let phaseChange = Animation.easeInOut(duration: 0.28)
}

// MARK: - Reduce Motion

/// Returns `animation` unless the user has asked iOS to reduce motion, in which
/// case it returns a short cross-fade.
///
/// Apply with `.animation(motion, value:)` so callers never branch themselves.
struct ReduceMotionAware: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation

    func body(content: Content) -> some View {
        content.transaction { transaction in
            transaction.animation = reduceMotion
                ? .easeOut(duration: 0.12)
                : animation
        }
    }
}

extension View {
    /// Applies `animation`, downgrading it to a brief fade under Reduce Motion.
    func accessibleAnimation(_ animation: Animation) -> some View {
        modifier(ReduceMotionAware(animation: animation))
    }
}
