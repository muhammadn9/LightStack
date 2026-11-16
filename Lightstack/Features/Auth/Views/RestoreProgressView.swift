import SwiftUI

/// Full-screen state shown after sign-in on a device that has no profile yet, while the app
/// looks for the account's cloud profile and history. Replaces the onboarding decision until
/// that is known.
struct RestoreProgressView: View {
    @EnvironmentObject var environment: AppEnvironment

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                if environment.restoreGate == .failed {
                    failedContent
                } else {
                    restoringContent
                }
            }
            .padding(32)
        }
    }

    private var restoringContent: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppTheme.accent)
                .scaleEffect(1.4)
            Text("Restoring your history…")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Looking for your account's workouts.")
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("restoreProgressView")
    }

    private var failedContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.warning)
            Text("Couldn't reach your account")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("restoreFailedView")
            Text("Check your connection and try again. Your workouts are safe in your account.")
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                environment.retryProfileRestore()
            } label: {
                Text("Retry")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(AppTheme.accent, in: Capsule())
            }
            .accessibilityIdentifier("restoreRetryButton")

            Button {
                environment.continueWithoutRestore()
            } label: {
                Text("Set up as new")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(AppTheme.surface, in: Capsule())
                    .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
            }
            .accessibilityIdentifier("restoreSetUpAsNewButton")
        }
    }
}
