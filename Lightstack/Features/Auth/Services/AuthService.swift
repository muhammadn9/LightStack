import Foundation
import AuthenticationServices
import Supabase

// MARK: - AuthServiceDelegate

protocol AuthServiceDelegate: AnyObject {
    func authServiceDidSignIn(_ service: AuthService)
    func authServiceDidSignOut(_ service: AuthService)
    func authService(_ service: AuthService, didFailWith error: Error)
}

// MARK: - AuthService

/// Handles all authentication: email sign-in/up, Apple Sign-In, and sign-out.
/// Uses Supabase Auth under the hood. Apple Sign-In uses ASAuthorizationController
/// via delegate — no closure callbacks.
final class AuthService: NSObject {

    weak var delegate: AuthServiceDelegate?

    private let supabaseClient: SupabaseClient

    // MARK: - Init

    override init() {
        let url = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
        let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""
        self.supabaseClient = SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: key
        )
        super.init()
    }

    // MARK: - Email Auth

    func signInWithEmail(email: String, password: String) {
        Task {
            do {
                try await supabaseClient.auth.signIn(
                    email: email,
                    password: password
                )
                await notifySignIn()
            } catch {
                await notifyError(error)
            }
        }
    }

    func signUpWithEmail(email: String, password: String) {
        Task {
            do {
                try await supabaseClient.auth.signUp(
                    email: email,
                    password: password
                )
                await notifySignIn()
            } catch {
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
