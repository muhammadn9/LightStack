import SwiftUI
import AuthenticationServices

/// Login screen: email/password fields + Sign in with Apple button.
struct LoginView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                headerSection
                emailFormSection
                appleSignInSection
                toggleModeSection
            }
            .padding(.horizontal, 24)
            .navigationTitle("Lightstack")
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 60))
                .foregroundStyle(.accent)
            Text("Your AI Strength Coach")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private var emailFormSection: some View {
        VStack(spacing: 16) {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(action: handleEmailAuth) {
                Text(isSignUp ? "Sign Up" : "Sign In")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty)
        }
    }

    private var appleSignInSection: some View {
        VStack(spacing: 12) {
            dividerWithText("or")
            SignInWithAppleButton(
                .signIn,
                onRequest: configureAppleRequest,
                onCompletion: handleAppleResult
            )
            .frame(height: 50)
            .signInWithAppleButtonStyle(.black)
        }
    }

    private var toggleModeSection: some View {
        Button(action: { isSignUp.toggle() }) {
            Text(isSignUp
                 ? "Already have an account? Sign In"
                 : "Don't have an account? Sign Up")
                .font(.footnote)
        }
    }

    // MARK: - Actions

    private func handleEmailAuth() {
        errorMessage = nil
        if isSignUp {
            environment.authService.signUpWithEmail(
                email: email,
                password: password
            )
        } else {
            environment.authService.signInWithEmail(
                email: email,
                password: password
            )
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

    // MARK: - Helpers

    private func dividerWithText(_ text: String) -> some View {
        HStack {
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
        }
    }
}
