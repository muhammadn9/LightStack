import Foundation
import AuthenticationServices
import Supabase

// MARK: - AuthServiceDelegate

protocol AuthServiceDelegate: AnyObject {
    func authServiceDidSignIn(_ service: AuthService)
    func authServiceDidSignOut(_ service: AuthService)
    func authServiceNeedsEmailVerification(_ service: AuthService, email: String)
    func authService(_ service: AuthService, didFailWith error: Error)
}

// MARK: - AuthService

/// Handles all authentication: email sign-in/up, Apple Sign-In, and sign-out.
/// Uses Supabase Auth under the hood.
final class AuthService: NSObject {

    weak var delegate: AuthServiceDelegate?

    let supabaseClient: SupabaseClient

    /// Redirect URL for email verification links — must match the
    /// CFBundleURLSchemes entry in Info.plist AND the "Redirect URLs"
    /// allow-list in the Supabase dashboard.
    static let redirectURL = URL(string: "lightstack://auth-callback")!

    // MARK: - Init

    init(client: SupabaseClient) {
        self.supabaseClient = client
        super.init()
    }

    override convenience init() {
        let url = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
        let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""
        let client = SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: key
        )
        self.init(client: client)
    }

    // MARK: - Email Auth

    func signInWithEmail(email: String, password: String) {
        Task {
            do {
                let session = try await supabaseClient.auth.signIn(
                    email: email,
                    password: password
                )
                if session.user.emailConfirmedAt == nil {
                    try? await supabaseClient.auth.signOut()
                    await notifyNeedsVerification(email: email)
                } else {
                    await notifySignIn()
                }
            } catch {
                await notifyError(error)
            }
        }
    }

    func signUpWithEmail(email: String, password: String) {
        Task {
            do {
                let response = try await supabaseClient.auth.signUp(
                    email: email,
                    password: password,
                    redirectTo: Self.redirectURL
                )
                // Supabase anti-enumeration: existing emails return a user
                // with empty identities and no session
                if case .user(let user) = response {
                    if (user.identities ?? []).isEmpty {
                        await notifyError(NSError(
                            domain: "AuthService",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "An account with this email already exists. Try signing in instead."]
                        ))
                        return
                    }
                }
                await notifyNeedsVerification(email: email)
            } catch {
                await notifyError(error)
            }
        }
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async throws {
        try await supabaseClient.auth.resetPasswordForEmail(email, redirectTo: Self.redirectURL)
    }

    // MARK: - Email Verification

    func resendVerificationEmail(email: String) {
        Task {
            do {
                try await supabaseClient.auth.resend(
                    email: email,
                    type: .signup
                )
            } catch {
                print("Resend verification error: \(error.localizedDescription)")
            }
        }
    }

    /// Checks if the user's email has been verified.
    /// Because sign-up doesn't create a session for unverified users,
    /// we need to attempt a fresh session refresh or sign-in check.
    func checkEmailVerified(email: String, password: String, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                // Try signing in — if email is confirmed, this succeeds with a valid session
                let session = try await supabaseClient.auth.signIn(
                    email: email,
                    password: password
                )
                let verified = session.user.emailConfirmedAt != nil
                if verified {
                    // Email confirmed — notify delegate to update app state
                    await notifySignIn()
                } else {
                    // Still not verified — sign back out
                    try? await supabaseClient.auth.signOut()
                }
                await MainActor.run { completion(verified) }
            } catch {
                await MainActor.run { completion(false) }
            }
        }
    }

    // MARK: - Deep Link Handling

    /// Call this when the app receives a deep link (lightstack://auth-callback?...).
    /// Supabase appends session tokens to the URL after email verification.
    func handleDeepLink(_ url: URL) {
        Task {
            do {
                let session = try await supabaseClient.auth.session(from: url)
                if session.user.emailConfirmedAt != nil {
                    await notifySignIn()
                }
            } catch {
                print("Deep link session error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Google Sign-In (OAuth via ASWebAuthenticationSession)

    func signInWithGoogle() {
        Task {
            do {
                try await supabaseClient.auth.signInWithOAuth(
                    provider: .google,
                    redirectTo: Self.redirectURL
                )
                await notifySignIn()
            } catch {
                // Don't report cancellation as an error
                let nsError = error as NSError
                if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession",
                   nsError.code == 1 {
                    return
                }
                await notifyError(error)
            }
        }
    }

    // MARK: - Apple Sign-In

    func signInWithApple() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(
            authorizationRequests: [request]
        )
        controller.delegate = self
        controller.performRequests()
    }

    // MARK: - Sign Out

    func signOut() {
        Task {
            do {
                try await supabaseClient.auth.signOut()
                await notifySignOut()
            } catch {
                await notifyError(error)
            }
        }
    }

    // MARK: - Current User

    func currentUser() -> UserProfile? {
        guard let user = supabaseClient.auth.currentUser else {
            return nil
        }
        return UserProfile(
            id: user.id,
            userId: user.id,
            displayName: nil,
            age: nil,
            heightInches: nil,
            weightLbs: nil,
            trainingAgeMonths: nil,
            primaryGoals: [],
            splitDays: [],
            avoidExercises: [],
            equipment: [:],
            customEquipment: nil,
            notesToCoach: nil,
            createdAt: user.createdAt,
            updatedAt: user.createdAt
        )
    }

    // MARK: - Private Helpers

    @MainActor
    private func notifySignIn() {
        delegate?.authServiceDidSignIn(self)
    }

    @MainActor
    private func notifySignOut() {
        delegate?.authServiceDidSignOut(self)
    }

    @MainActor
    private func notifyNeedsVerification(email: String) {
        delegate?.authServiceNeedsEmailVerification(self, email: email)
    }

    @MainActor
    private func notifyError(_ error: Error) {
        delegate?.authService(self, didFailWith: error)
    }

    private func handleAppleCredential(
        _ credential: ASAuthorizationAppleIDCredential
    ) {
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8)
        else {
            let error = NSError(
                domain: "AuthService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing Apple ID token"]
            )
            Task { await notifyError(error) }
            return
        }
        Task {
            do {
                try await supabaseClient.auth.signInWithIdToken(
                    credentials: .init(
                        provider: .apple,
                        idToken: tokenString
                    )
                )
                await notifySignIn()
            } catch {
                await notifyError(error)
            }
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential
                as? ASAuthorizationAppleIDCredential else {
            return
        }
        handleAppleCredential(credential)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { await notifyError(error) }
    }
}
