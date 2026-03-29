import SwiftUI

/// Root view that routes between Login, Email Verification, Onboarding,
/// and the main tab bar based on authentication and onboarding state.
struct RootView: View {
    @EnvironmentObject var environment: AppEnvironment

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
    }
}
