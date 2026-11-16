import SwiftUI
import AuthenticationServices

/// Welcome screen: three equal sign-in choices. Email lives on its own screen.
struct LoginView: View {
    @EnvironmentObject var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @State private var errorMessage: String?
    /// Raw nonce for the in-flight Apple request; its SHA-256 goes on the request.
    @State private var appleNonce: String?
    @State private var showEmail = false
    @State private var legalDocument: LegalDocument?

    private let buttonHeight: CGFloat = 54

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                header
                Spacer(minLength: 24)
                actions
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationDestination(isPresented: $showEmail) {
                EmailAuthView(errorMessage: $errorMessage)
            }
        }
        .sheet(item: $legalDocument) { LegalSheet(document: $0) }
        .onChange(of: environment.authErrorMessage) { _, newValue in
            if let message = newValue {
                errorMessage = message
                environment.authErrorMessage = nil
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 16) {
            AppIconMark(size: 96)
            Text("Lightstack")
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.textPrimary)
            Text(AuthCopy.tagline)
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                AuthErrorLabel(message: errorMessage)
            }

            SignInWithAppleButton(
                .continue,
                onRequest: configureAppleRequest,
                onCompletion: handleAppleResult
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: buttonHeight)
            .clipShape(Capsule())
            .accessibilityIdentifier("auth.apple")

            choiceButton("Continue with Google", systemImage: "g.circle.fill", id: "auth.google") {
                errorMessage = nil
                environment.authService.signInWithGoogle()
            }

            choiceButton("Continue with email", systemImage: "envelope.fill", id: "auth.email") {
                errorMessage = nil
                showEmail = true
            }

            legalLine
                .padding(.top, 8)
        }
    }

    private func choiceButton(_ title: String, systemImage: String, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: buttonHeight)
            .background(AppTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var legalLine: some View {
        VStack(spacing: 2) {
            Text("By continuing you agree to the")
            HStack(spacing: 4) {
                linkButton("Terms", id: "auth.terms", document: .terms)
                Text("and")
                linkButton("Privacy Policy", id: "auth.privacy", document: .privacy)
                Text(".").padding(.leading, -4)
            }
        }
        .font(.footnote)
        .foregroundStyle(AppTheme.textSecondary)
        .multilineTextAlignment(.center)
    }

    private func linkButton(_ title: String, id: String, document: LegalDocument) -> some View {
        Button(title) { legalDocument = document }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .accessibilityIdentifier(id)
    }

    // MARK: - Apple

    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        let nonce = AuthService.appleNonce()
        appleNonce = nonce.raw
        request.nonce = nonce.hashed
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = appleNonce else {
                errorMessage = "Apple Sign-In failed. Please try again."
                return
            }
            appleNonce = nil
            environment.authService.signInWithApple(credential: credential, nonce: nonce)
        case .failure:
            errorMessage = "Apple Sign-In cancelled."
        }
    }
}

/// Inline, readable auth error.
struct AuthErrorLabel: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .foregroundStyle(AppTheme.destructive)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.destructive.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("auth.error")
    }
}
