import SwiftUI

/// Email sign-in and sign-up, pushed from the welcome screen.
struct EmailAuthView: View {
    @EnvironmentObject var environment: AppEnvironment
    @Binding var errorMessage: String?

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var showResetConfirmation = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool { !email.isEmpty && !password.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isSignUp ? "Create your account" : "Welcome back")
                    .font(.title.bold())
                    .foregroundStyle(AppTheme.textPrimary)

                Picker("Mode", selection: $isSignUp) {
                    Text("Sign in").tag(false)
                    Text("Create account").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("auth.mode")

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                        .fieldStyle()
                        .accessibilityIdentifier("auth.email.field")

                    SecureField("Password", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                        .submitLabel(.go)
                        .focused($focus, equals: .password)
                        .onSubmit { if canSubmit { handleEmailAuth() } }
                        .fieldStyle()
                        .accessibilityIdentifier("auth.password.field")
                }

                if !isSignUp {
                    Button("Forgot password?", action: handleForgotPassword)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityIdentifier("auth.forgot")
                }

                if showResetConfirmation {
                    Label("Check your email for a password reset link", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityIdentifier("auth.resetConfirmation")
                }

                if let errorMessage {
                    AuthErrorLabel(message: errorMessage)
                }

                Button(action: handleEmailAuth) {
                    Text(isSignUp ? "Create account" : "Sign in")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canSubmit ? AppTheme.onAccent : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(canSubmit ? AppTheme.accent : AppTheme.surfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .accessibilityIdentifier("auth.submit")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Email")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isSignUp) { _, _ in
            errorMessage = nil
            showResetConfirmation = false
        }
    }

    // MARK: - Actions (same behaviour as before)

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
                showResetConfirmation = false
                errorMessage = AuthService.resetPasswordMessage(for: error)
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
}

private extension View {
    func fieldStyle() -> some View {
        self
            .font(.body)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .foregroundStyle(AppTheme.textPrimary)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.border, lineWidth: 1))
    }
}
