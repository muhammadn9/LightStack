import SwiftUI

/// Shown after sign-up until the user verifies their email.
/// Provides resend, check verification, and sign-out options.
struct EmailVerificationView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var isChecking = false
    @State private var errorMessage: String?
    @State private var cooldownRemaining = 0
    @State private var cooldownTimer: Timer?

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()
                iconSection
                messageSection
                buttonsSection
                Spacer()
                differentEmailButton
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Sections

    private var iconSection: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accent.opacity(0.15))
                .frame(width: 120, height: 120)
            Circle()
                .fill(AppTheme.accent.opacity(0.08))
                .frame(width: 160, height: 160)
            Image(systemName: "envelope.badge")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.accent)
        }
    }

    private var messageSection: some View {
        VStack(spacing: 12) {
            Text("Check your email")
                .font(.title.bold())
                .foregroundStyle(AppTheme.textPrimary)

            if let email = environment.pendingVerificationEmail {
                Text("We sent a verification link to")
                    .foregroundStyle(AppTheme.textSecondary)
                Text(email)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.accentSecondary)
            }

            Text("Tap the link in the email, then come back and tap the button below.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    private var buttonsSection: some View {
        VStack(spacing: 14) {
            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage)
                }
                .font(.caption)
                .foregroundStyle(AppTheme.destructive)
            }

            Button(action: checkVerification) {
                HStack {
                    if isChecking {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("I've verified my email")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .disabled(isChecking)

            Button(action: resendEmail) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text(cooldownRemaining > 0
                         ? "Resend in \(cooldownRemaining)s"
                         : "Resend Email")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(cooldownRemaining > 0 ? AppTheme.textSecondary : AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .disabled(cooldownRemaining > 0)
        }
    }

    private var differentEmailButton: some View {
        Button(action: useDifferentEmail) {
            Text("Use a different email")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Actions

    private func checkVerification() {
        guard let email = environment.pendingVerificationEmail,
              let password = environment.pendingVerificationPassword else {
            errorMessage = "Please sign up again."
            return
        }
        isChecking = true
        errorMessage = nil
        environment.authService.checkEmailVerified(email: email, password: password) { verified in
            isChecking = false
            if verified {
                // Sign-in succeeded with confirmed email — AuthService delegate
                // will fire authServiceDidSignIn, which sets isAuthenticated = true
                // and clears needsEmailVerification
            } else {
                errorMessage = "Email not verified yet. Please check your inbox."
            }
        }
    }

    private func resendEmail() {
        guard let email = environment.pendingVerificationEmail else { return }
        environment.authService.resendVerificationEmail(email: email)
        startCooldown()
    }

    private func useDifferentEmail() {
        environment.authService.signOut()
        environment.needsEmailVerification = false
        environment.pendingVerificationEmail = nil
        environment.pendingVerificationPassword = nil
    }

    private func startCooldown() {
        cooldownRemaining = 60
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            cooldownRemaining -= 1
            if cooldownRemaining <= 0 {
                timer.invalidate()
            }
        }
    }
}
