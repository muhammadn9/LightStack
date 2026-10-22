import Foundation
import AuthenticationServices
import CryptoKit
import Supabase
import GoogleSignIn
import UIKit
import os

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

    private let logger = Logger(subsystem: "org.lightstack.app", category: "AuthService")

    weak var delegate: AuthServiceDelegate?

    /// Runs at most one Google attempt; a new tap supersedes (and unblocks) a stale one.
    @MainActor let googleAttempts = LatestAttemptRunner()

    let supabaseClient: SupabaseClient

    /// Redirect URL for email verification links — must match the
    /// CFBundleURLSchemes entry in Info.plist AND the "Redirect URLs"
    /// allow-list in the Supabase dashboard.
    static let redirectURL: URL = {
        guard let url = URL(string: "lightstack://auth-callback") else {
            preconditionFailure("Malformed static redirect URL")
        }
        return url
    }()

    // MARK: - Init

    init(client: SupabaseClient) {
        self.supabaseClient = client
        super.init()
    }

    override convenience init() {
        let url = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
        let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""
        guard let resolvedURL = URL(string: url), !url.isEmpty else {
            let logger = Logger(subsystem: "org.lightstack.app", category: "AuthService")
            logger.critical("SUPABASE_URL is missing or invalid — add a valid URL in Secrets.xcconfig")
            fatalError("SUPABASE_URL is missing or invalid — add a valid URL in Secrets.xcconfig")
        }
        let client = SupabaseClient(
            supabaseURL: resolvedURL,
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

    /// A human-readable reason a reset request failed, so a server-side problem
    /// (mail provider down, rate limit, no network) is never shown as nothing at all.
    static func resetPasswordMessage(for error: Error) -> String {
        if let authError = error as? AuthError, case .api(let message, let code, _, let response) = authError {
            if code == .overEmailSendRateLimit {
                return "Too many reset emails requested. Please wait a few minutes and try again."
            }
            if response.statusCode >= 500 {
                return "We couldn't send the reset email right now. Please try again later. (\(message))"
            }
            return message
        }
        if error is URLError {
            return "Couldn't reach the server. Check your connection and try again."
        }
        let text = error.localizedDescription
        return text.isEmpty ? "Couldn't send the reset email. Please try again." : text
    }

    func resetPassword(email: String) async throws {
        do {
            try await supabaseClient.auth.resetPasswordForEmail(email, redirectTo: Self.redirectURL)
        } catch {
            logger.error("Password reset failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
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
                self.logger.error("Resend verification error: \(error.localizedDescription)")
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

    /// Routes incoming deep links. Google reversed-client-ID callbacks go to GIDSignIn;
    /// everything else goes to the Supabase session handler (email verification, etc.).
    func handleDeepLink(_ url: URL) {
        let reversedClientID = Bundle.main.infoDictionary?["GOOGLE_REVERSED_CLIENT_ID"] as? String ?? ""
        if !reversedClientID.isEmpty,
           url.scheme?.lowercased() == reversedClientID.lowercased() {
            _ = GIDSignIn.sharedInstance.handle(url)
            return
        }
        // Only our own auth callback reaches Supabase; anything else is ignored.
        guard Self.isAuthCallback(url) else {
            logger.info("Ignored unexpected deep link")
            return
        }
        Task {
            do {
                let session = try await supabaseClient.auth.session(from: url)
                if session.user.emailConfirmedAt != nil {
                    await notifySignIn()
                }
            } catch {
                self.logger.error("Deep link session error: \(error.localizedDescription)")
            }
        }
    }

    /// `lightstack://auth-callback?…` — the redirect Supabase uses for email links.
    static func isAuthCallback(_ url: URL) -> Bool {
        url.scheme?.lowercased() == redirectURL.scheme?.lowercased()
            && url.host?.lowercased() == redirectURL.host?.lowercased()
    }

    // MARK: - Google Sign-In

    @MainActor
    func signInWithGoogle() {
        // A tappable button means no Google sheet is on screen, so any attempt still
        // "running" is stale (e.g. a cancelled flow that never reported back). Supersede
        // it rather than ignore the tap, so the button can never stay dead.
        if googleAttempts.isRunning {
            logger.info("Google Sign-In: superseding a stale attempt")
        }
        googleAttempts.start { [weak self] in
            guard let self else { return }
            let clientID = Bundle.main.infoDictionary?["GOOGLE_CLIENT_ID"] as? String ?? ""

            // Primary path: native GoogleSignIn SDK (requires GOOGLE_CLIENT_ID to be set)
            if !clientID.isEmpty {
                await self.signInWithGoogleNative(clientID: clientID)
            } else {
                // The SDK isn't configured: the only case where the web flow is the right path.
                self.logger.info("Google Sign-In: GOOGLE_CLIENT_ID not set, using ephemeral web fallback")
                await self.signInWithGoogleEphemeral()
            }
        }
    }

    /// Bridges a callback API to async such that task cancellation resumes the await
    /// (with `CancellationError`) and the callback can only resume it once.
    static func awaitCancellable<T>(
        _ start: (@escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        let box = ResumeOnce<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
                box.install(cont)
                start { box.finish($0) }
            }
        } onCancel: {
            box.finish(.failure(CancellationError()))
        }
    }

    /// Runs the native Google flow and exchanges the result with Supabase using a nonce pair:
    /// Google gets the SHA-256 (`hashed`) and puts it in the ID token; Supabase gets the raw
    /// value and hashes it itself before comparing. `obtainTokens` and `exchange` are seams
    /// so tests can verify the pairing without Google or the network.
    static func performGoogleExchange(
        nonce: (raw: String, hashed: String) = appleNonce(),
        obtainTokens: (_ hashedNonce: String) async throws -> (idToken: String, accessToken: String),
        exchange: (_ idToken: String, _ accessToken: String, _ rawNonce: String) async throws -> Void
    ) async throws {
        let tokens = try await obtainTokens(nonce.hashed)
        try await exchange(tokens.idToken, tokens.accessToken, nonce.raw)
    }

    @MainActor
    private func signInWithGoogleNative(clientID: String) async {
        // Find presenting UIViewController from the active window scene
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            logger.error("Google Sign-In: no presenting view controller found")
            notifyError(NSError(
                domain: "AuthService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't open Google Sign-In. Please try again."]
            ))
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        // Start from a clean slate so a previous account/attempt can't leak into this one.
        GIDSignIn.sharedInstance.signOut()

        // Present from the top-most controller so the Google sheet never fights another presentation.
        var presenter = rootVC
        // Skip a controller that is mid-dismissal (a just-cancelled Google sheet): presenting
        // from it fails silently and the attempt would never report back.
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }

        logger.info("Google Sign-In: presenting from \(String(describing: type(of: presenter)), privacy: .public) (window attached: \(presenter.view.window != nil, privacy: .public))")
        do {
            try await Self.performGoogleExchange(
                obtainTokens: { hashedNonce in
                    // Cancellation-aware: cancelling the attempt resumes this await even if
                    // the SDK never calls back.
                    try await Self.awaitCancellable { finish in
                        GIDSignIn.sharedInstance.signIn(
                            withPresenting: presenter,
                            hint: nil,
                            additionalScopes: nil,
                            nonce: hashedNonce
                        ) { result, error in
                            if let error {
                                finish(.failure(error))
                            } else if let idToken = result?.user.idToken?.tokenString,
                                      let access = result?.user.accessToken.tokenString {
                                finish(.success((idToken, access)))
                            } else {
                                finish(.failure(NSError(
                                    domain: "AuthService",
                                    code: -3,
                                    userInfo: [NSLocalizedDescriptionKey: "Google Sign-In did not return an ID token."]
                                )))
                            }
                        }
                    }
                },
                exchange: { [supabaseClient, logger] idToken, accessToken, rawNonce in
                    logger.info("Google Sign-In: native path succeeded, exchanging tokens with Supabase")
                    try await supabaseClient.auth.signInWithIdToken(
                        credentials: .init(
                            provider: .google,
                            idToken: idToken,
                            accessToken: accessToken,
                            nonce: rawNonce
                        )
                    )
                }
            )
            // A superseded/cancelled attempt must not sign in or report anything.
            guard !Task.isCancelled else { return }
            notifySignIn()
        } catch is CancellationError {
            logger.info("Google Sign-In: attempt cancelled")
        } catch let error as GIDSignInError where error.code == .canceled {
            // User cancelled — silent no-op
            logger.info("Google Sign-In: user cancelled native flow")
        } catch {
            guard !Task.isCancelled else { return }
            // No silent second flow: a failed exchange is surfaced so it can be diagnosed.
            logger.error("Google Sign-In: native flow failed (\(error.localizedDescription, privacy: .public))")
            GIDSignIn.sharedInstance.signOut()
            notifyError(error)
        }
    }

    @MainActor
    private func signInWithGoogleEphemeral() async {
        logger.info("Google Sign-In: using ephemeral ASWebAuthenticationSession (no host-disclosure alert)")
        do {
            try await supabaseClient.auth.signInWithOAuth(
                provider: .google,
                redirectTo: Self.redirectURL
            ) { (session: ASWebAuthenticationSession) in
                session.prefersEphemeralWebBrowserSession = true
            }
            await notifySignIn()
        } catch {
            // Don't report user cancellation as an error
            let nsError = error as NSError
            if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession",
               nsError.code == 1 {
                logger.info("Google Sign-In: user cancelled ephemeral web session")
                return
            }
            await notifyError(error)
        }
    }

    // MARK: - Apple Sign-In

    /// Signs in with the credential from `SignInWithAppleButton`. `nonce` is the raw
    /// value whose SHA-256 was put on the request (see `appleNonce()`); Supabase checks
    /// it against the ID token so a stolen token can't be replayed.
    func signInWithApple(credential: ASAuthorizationAppleIDCredential, nonce: String) {
        handleAppleCredential(credential, nonce: nonce)
    }

    /// A fresh random nonce, and its SHA-256 for `ASAuthorizationAppleIDRequest.nonce`.
    static func appleNonce() -> (raw: String, hashed: String) {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        let raw = String((0..<32).map { _ in charset[Int.random(in: 0..<charset.count, using: &generator)] })
        let hashed = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return (raw, hashed)
    }

    // MARK: - Sign Out

    func signOut() {
        CoachDebugStore.shared.clear()
        Task {
            do {
                try await supabaseClient.auth.signOut()
                await resetGoogleState()
                await notifySignOut()
            } catch {
                await notifyError(error)
            }
        }
    }

    /// Forget the Google account and any pending attempt so the next sign-in starts clean
    /// and can pick a different account.
    @MainActor
    private func resetGoogleState() {
        GIDSignIn.sharedInstance.signOut()
        googleAttempts.cancel()
    }

    // MARK: - Current User

    func currentUser() -> UserProfile? {
        #if DEBUG
        if UITestMode.isActive { return UITestMode.testUser }
        #endif
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
        _ credential: ASAuthorizationAppleIDCredential,
        nonce: String
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
                        idToken: tokenString,
                        nonce: nonce
                    )
                )
                await notifySignIn()
            } catch {
                await notifyError(error)
            }
        }
    }
}

// MARK: - Attempt state machine

/// Resumes a continuation at most once, whichever of callback/cancellation comes first.
final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var early: Result<T, Error>?
    private var done = false

    func install(_ cont: CheckedContinuation<T, Error>) {
        lock.lock()
        if let early {
            done = true
            lock.unlock()
            cont.resume(with: early)
        } else {
            continuation = cont
            lock.unlock()
        }
    }

    func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        if let cont = continuation {
            done = true
            continuation = nil
            lock.unlock()
            cont.resume(with: result)
        } else {
            early = early ?? result   // cancelled/finished before install
            lock.unlock()
        }
    }
}

/// Holds the single current attempt. Starting a new one cancels the previous; an old
/// attempt finishing late can never clear the new one's state.
@MainActor
final class LatestAttemptRunner {
    private var task: Task<Void, Never>?
    private var currentID = UUID()

    var isRunning: Bool { task != nil }

    func start(_ body: @escaping @MainActor () async -> Void) {
        task?.cancel()
        let id = UUID()
        currentID = id
        task = Task { @MainActor [weak self] in
            await body()
            if self?.currentID == id { self?.task = nil }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        currentID = UUID()
    }

    /// Test helper: waits for the current attempt to finish.
    func waitUntilIdle() async {
        await task?.value
    }
}
