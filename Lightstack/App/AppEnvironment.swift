import Foundation
import SwiftUI

/// DI container and shared environment object.
/// Owns all service and repository singletons.
/// Conforms to AuthServiceDelegate to propagate auth state changes.
final class AppEnvironment: ObservableObject, AuthServiceDelegate {

    // MARK: - Auth State

    @Published var isAuthenticated: Bool = false
    @Published var hasCompletedOnboarding: Bool = false

    // MARK: - Services

    let authService: AuthService
    let supabaseService: SupabaseService
    let localStorageService: LocalStorageService
    let syncService: SyncService
    let validationService: ValidationService

    // MARK: - Repositories

    let workoutRepository: WorkoutRepository
    let profileRepository: ProfileRepository
    let prRepository: PRRepository
    let monthPlanRepository: MonthPlanRepository

    // MARK: - Init

    init() {
        self.authService = AuthService()
        self.supabaseService = SupabaseService()
        self.localStorageService = LocalStorageService()
        self.syncService = SyncService()
        self.validationService = ValidationService()

        self.workoutRepository = WorkoutRepository()
        self.profileRepository = ProfileRepository()
        self.prRepository = PRRepository()
        self.monthPlanRepository = MonthPlanRepository()

        authService.delegate = self
        checkExistingSession()
    }

    // MARK: - AuthServiceDelegate

    func authServiceDidSignIn(_ service: AuthService) {
        isAuthenticated = true
    }

    func authServiceDidSignOut(_ service: AuthService) {
        isAuthenticated = false
        hasCompletedOnboarding = false
    }

    func authService(_ service: AuthService, didFailWith error: Error) {
        // TODO: Phase 1 — Surface auth errors to the UI
    }

    // MARK: - Private

    private func checkExistingSession() {
        isAuthenticated = authService.currentUser() != nil
    }
}
