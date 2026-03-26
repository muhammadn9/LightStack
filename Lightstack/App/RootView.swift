import SwiftUI

/// Root view that routes between Login, Onboarding, and the main tab bar
/// based on authentication and onboarding state.
struct RootView: View {
    @EnvironmentObject var environment: AppEnvironment

    var body: some View {
        Group {
            if !environment.isAuthenticated {
                LoginView()
            } else if !environment.hasCompletedOnboarding {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
    }
}
