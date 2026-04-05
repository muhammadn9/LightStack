import SwiftUI
import AuthenticationServices

/// Login screen with purple radiant dark theme.
struct LoginView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var errorMessage: String?
    @State private var showResetConfirmation = false

    var body: some View {
        ZStack {
            // Background
            AppTheme.backgroundGradient.ignoresSafeArea()

            // Subtle purple glow at top
            VStack {
                Ellipse()
                    .fill(AppTheme.accent.opacity(0.08))
                    .frame(width: 400, height: 250)
                    .blur(radius: 60)
                    .offset(y: -80)
                Spacer()
            }
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    formCard
                    socialSignInSection
                    toggleModeSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
            }
        }
        .onChange(of: environment.authErrorMessage) { _, newValue in
            if let message = newValue {
                errorMessage = message
                environment.authErrorMessage = nil
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 44))
                    .foregroundStyle(AppTheme.accent)
            }

            Text("Lightstack")
                .font(AppTheme.playfairItalic(40, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Your AI Strength Coach")
                .font(AppTheme.caveat(18))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var formCard: some View {
        VStack(spacing: 16) {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .padding(14)
                .background(AppTheme.surfaceElevated)
                .foregroundStyle(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

            SecureField("Password", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .padding(14)
                .background(AppTheme.surfaceElevated)
                .foregroundStyle(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

            if !isSignUp {
                HStack {
                    Spacer()
                    Button("Forgot password?") {
                        handleForgotPassword()
                    }
                    .font(AppTheme.caveat(12))
                    .foregroundStyle(AppTheme.accentSecondary)
                }
            }

            if showResetConfirmation {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Check your email for a password reset link")
                }
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.accent)
            }

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage)
                }
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.destructive)
            }

            Button(action: handleEmailAuth) {
                Text(isSignUp ? "Sign Up" : "Sign In")
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .disabled(email.isEmpty || password.isEmpty)
            .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1)
        }
        .padding(20)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .shadow(color: Color.purple.opacity(0.15), radius: 12, x: 0, y: 4)
    }

    private var socialSignInSection: some View {
        VStack(spacing: 12) {
            dividerWithText("or")

            // Google Sign-In
            Button(action: { environment.authService.signInWithGoogle() }) {
                HStack(spacing: 10) {
                    Image(systemName: "g.circle.fill")
                        .font(.title2)
                    Text("Sign in with Google")
                        .font(AppTheme.playfairItalic(16, weight: .bold))
                }
                .foregroundStyle(AppTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.surfaceElevated, lineWidth: 1)
                )
            }

            // Apple Sign-In
            SignInWithAppleButton(
                .signIn,
                onRequest: configureAppleRequest,
                onCompletion: handleAppleResult
            )
            .frame(height: 50)
            .signInWithAppleButtonStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }

    private var toggleModeSection: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) { isSignUp.toggle() }
        }) {
            Text(isSignUp
                 ? "Already have an account? Sign In"
                 : "Don't have an account? Sign Up")
                .font(AppTheme.caveat(12))
                .foregroundStyle(AppTheme.accentSecondary)
        }
    }

    // MARK: - Actions

    private func handleForgotPassword() {
        errorMessage = nil
        showResetConfirmation = false
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter your email address first"
            return
        }
        Task {
            do {
                try await environment.authService.resetPassword(email: email)
                showResetConfirmation = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleEmailAuth() {
        errorMessage = nil
        showResetConfirmation = false
        // Store password so EmailVerificationView can re-sign-in to check verification
        environment.pendingVerificationPassword = password
        if isSignUp {
            environment.authService.signUpWithEmail(email: email, password: password)
        } else {
            environment.authService.signInWithEmail(email: email, password: password)
        }
    }

    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success:
            environment.authService.signInWithApple()
        case .failure:
            errorMessage = "Apple Sign-In cancelled."
        }
    }

    private func dividerWithText(_ text: String) -> some View {
        HStack {
            InkDivider()
            Text(text).font(AppTheme.caveat(11)).foregroundStyle(AppTheme.textSecondary)
            InkDivider()
        }
    }
}
