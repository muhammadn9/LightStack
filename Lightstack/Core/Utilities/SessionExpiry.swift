import Foundation
import Supabase

extension SyncErrorClassifier {
    /// True when an error from a session refresh / token fetch means the stored session is dead for
    /// good (revoked or expired refresh token), as opposed to being offline or a server hiccup.
    static func isSessionRejected(_ error: Error) -> Bool {
        if error is URLError || error is CancellationError { return false }
        if let auth = error as? AuthError {
            switch auth {
            case .sessionMissing, .refreshDiscarded: return true
            case .api(_, _, _, let response):
                let code = response.statusCode
                return (400...499).contains(code) && code != 408 && code != 429
            default: return false
            }
        }
        return classify(error, opType: .insertWorkout) == .auth
    }
}

/// Remembers which user's session expired or was revoked. Local data and queued operations are never
/// touched: the flag only drives the "signed out" banner and the resume-after-sign-in decision.
final class SessionExpiryTracker: @unchecked Sendable {

    enum SignInOutcome: Equatable {
        /// No expiry was pending.
        case notExpired
        /// The same user signed in again: resume uploading their queued changes.
        case resumed
        /// Someone else signed in: the expired user's changes stay queued under their own id.
        case differentUser
    }

    static let defaultsKey = "lightstack.expiredSessionUserId"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The user whose session expired, if any (persisted so it survives a relaunch).
    var expiredUserId: UUID? {
        lock.lock(); defer { lock.unlock() }
        return defaults.string(forKey: Self.defaultsKey).flatMap(UUID.init(uuidString:))
    }

    var isExpired: Bool { expiredUserId != nil }

    func markExpired(userId: UUID) {
        lock.lock(); defer { lock.unlock() }
        defaults.set(userId.uuidString, forKey: Self.defaultsKey)
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    /// Call when any user finishes signing in. Clears the expiry either way.
    func handleSignIn(userId: UUID) -> SignInOutcome {
        lock.lock(); defer { lock.unlock() }
        guard let expired = defaults.string(forKey: Self.defaultsKey).flatMap(UUID.init(uuidString:)) else {
            return .notExpired
        }
        defaults.removeObject(forKey: Self.defaultsKey)
        return expired == userId ? .resumed : .differentUser
    }
}
