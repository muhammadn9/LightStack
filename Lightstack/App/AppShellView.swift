import SwiftUI
import UIKit

/// The two halves of the app. Each has its own tab bar; the switch button flips between them.
enum AppSide: String {
    case gym, nutrition

    var other: AppSide { self == .gym ? .nutrition : .gym }
    /// Icon of the side you would switch TO (shown on the button).
    var switchIcon: String { self == .gym ? "fork.knife" : "dumbbell.fill" }
    var switchLabel: String { self == .gym ? "Switch to nutrition" : "Switch to training" }
    var accent: Color { self == .gym ? AppTheme.accent : AppTheme.nutritionAccent }
}

/// Owns which side is showing, persists it, and runs the switch animation.
/// Both sides stay alive once visited, so an active workout is never reset by switching.
@MainActor
final class AppSideController: ObservableObject {
    static let storageKey = "appSide"

    struct Reveal: Equatable {
        var target: AppSide
        var origin: CGPoint
        var swapped = false
    }

    @Published private(set) var side: AppSide
    @Published private(set) var nutritionMounted: Bool
    @Published private(set) var reveal: Reveal?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = AppSide(rawValue: defaults.string(forKey: Self.storageKey) ?? "") ?? .gym
        let initial: AppSide = FeatureFlags.nutritionTabEnabled ? stored : .gym
        side = initial
        nutritionMounted = initial == .nutrition
    }

    private func apply(_ target: AppSide) {
        side = target
        if target == .nutrition { nutritionMounted = true }
        defaults.set(target.rawValue, forKey: Self.storageKey)
    }

    /// Switches to the other side with a circular reveal from `origin` (global coordinates).
    func switchSide(from origin: CGPoint) {
        guard FeatureFlags.nutritionTabEnabled, reveal == nil else { return }
        let target = side.other
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if UIAccessibility.isReduceMotionEnabled {
            withAnimation(.easeInOut(duration: 0.25)) { apply(target) }
            return
        }
        reveal = Reveal(target: target, origin: origin)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { apply(target) }
            reveal?.swapped = true
            try? await Task.sleep(for: .milliseconds(360))
            reveal = nil
        }
    }
}

/// Hosts both sides. The gym side is always mounted; the nutrition side mounts on first visit and then stays.
struct AppShellView: View {
    @StateObject private var controller = AppSideController()

    var body: some View {
        ZStack {
            MainTabView()
                .opacity(controller.side == .gym ? 1 : 0)
                .allowsHitTesting(controller.side == .gym)
                .accessibilityHidden(controller.side != .gym)
            if controller.nutritionMounted {
                NutritionRootView()
                    .opacity(controller.side == .nutrition ? 1 : 0)
                    .allowsHitTesting(controller.side == .nutrition)
                    .accessibilityHidden(controller.side != .nutrition)
            }
        }
        .overlay {
            if let reveal = controller.reveal {
                SideRevealOverlay(reveal: reveal)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .environmentObject(controller)
    }
}

/// Full-screen circle that grows from the button in the destination's accent with its icon, then fades out.
private struct SideRevealOverlay: View {
    let reveal: AppSideController.Reveal
    @State private var grown = false

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            let origin = CGPoint(x: reveal.origin.x - frame.minX, y: reveal.origin.y - frame.minY)
            let radius = hypot(max(origin.x, proxy.size.width - origin.x), max(origin.y, proxy.size.height - origin.y))
            ZStack {
                Circle()
                    .fill(reveal.target.accent)
                    .frame(width: radius * 2, height: radius * 2)
                    .scaleEffect(grown ? 1 : 0.02)
                    .position(origin)
                Image(systemName: reveal.target == .nutrition ? "fork.knife" : "dumbbell.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(AppTheme.onAccent)
                    .scaleEffect(grown ? 1 : 0.3)
                    .opacity(grown ? 1 : 0)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .opacity(reveal.swapped ? 0 : 1)
            .animation(.easeOut(duration: 0.34), value: reveal.swapped)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeIn(duration: 0.36)) { grown = true } }
    }
}

// MARK: - Button

private struct SwitchButtonCenterKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

/// Small round button that flips between the training and nutrition sides.
struct SideSwitchButton: View {
    @EnvironmentObject private var controller: AppSideController
    @State private var center: CGPoint = .zero

    var body: some View {
        if FeatureFlags.nutritionTabEnabled {
            Button {
                controller.switchSide(from: center)
            } label: {
                Image(systemName: controller.side.switchIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(controller.side.other.accent)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.surfaceElevated, in: Circle())
                    .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear.preference(key: SwitchButtonCenterKey.self, value: CGPoint(x: frame.midX, y: frame.midY))
                }
            )
            .onPreferenceChange(SwitchButtonCenterKey.self) { center = $0 }
            .accessibilityLabel(controller.side.switchLabel)
            .accessibilityIdentifier("side.switch")
        }
    }
}
