import SwiftUI

/// Root view that routes between Login, Email Verification, Onboarding,
/// and the main tab bar based on authentication and onboarding state.
struct RootView: View {
    @EnvironmentObject var environment: AppEnvironment
    @AppStorage("appColorScheme") private var colorSchemePref = "system"
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        Group {
            if environment.needsEmailVerification {
                EmailVerificationView()
            } else if !environment.isAuthenticated {
                LoginView()
            } else if !environment.hasCompletedOnboarding {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: environment.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: environment.needsEmailVerification)
        .animation(.easeInOut(duration: 0.3), value: environment.hasCompletedOnboarding)
        .onAppear { applyColorScheme(colorSchemePref) }
        .onChange(of: colorSchemePref) { _, newValue in applyColorScheme(newValue) }
        .onChange(of: systemColorScheme) { _, _ in
            if colorSchemePref == "system" {
                applyColorScheme("system")
            }
        }
    }

    private func applyColorScheme(_ pref: String) {
        let style: UIUserInterfaceStyle
        switch pref {
        case "light": style = .light
        case "dark":  style = .dark
        default:      style = .unspecified
        }
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach { $0.overrideUserInterfaceStyle = style }
    }
}
