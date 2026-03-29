import Foundation
import SwiftUI
import Supabase

/// DI container and shared environment object.
/// Owns all service and repository singletons.
/// Conforms to AuthServiceDelegate to propagate auth state changes.
final class AppEnvironment: ObservableObject, AuthServiceDelegate {

    // MARK: - Auth State

    @Published var isAuthenticated: Bool = false
    @Published var hasCompletedOnboarding: Bool = false
    @Published var needsEmailVerification: Bool = false
    @Published var pendingVerificationEmail: String?
    @Published var authErrorMessage: String?
    /// Temporarily stored so "I've verified" can re-sign-in to confirm.
    /// Cleared on successful sign-in or sign-out.
    var pendingVerificationPassword: String?

    // MARK: - Shared Client

    let supabaseClient: SupabaseClient

    // MARK: - Services

    let authService: AuthService
    let supabaseService: SupabaseService
    let localStorageService: LocalStorageService
    let syncService: SyncService
    let validationService: ValidationService
    let geminiService: GeminiService
    let coachPromptService: CoachPromptService
    let workoutStatsService: WorkoutStatsService

    // MARK: - Repositories

    let workoutRepository: WorkoutRepository
    let profileRepository: ProfileRepository
    let prRepository: PRRepository
    let monthPlanRepository: MonthPlanRepository

    // MARK: - AI + Session Services

    let coachContextBuilder: CoachContextBuilder
    let workoutSessionService: WorkoutSessionService
    let monthPlanService: MonthPlanService

    // MARK: - Init

    init() {
        let url = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
        let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""
        self.supabaseClient = SupabaseClient(
            supabaseURL: URL(string: url) ?? URL(string: "https://placeholder.supabase.co")!,
            supabaseKey: key,
            options: .init(
                auth: .init(
                    redirectToURL: AuthService.redirectURL
                )
            )
        )

        self.authService = AuthService(client: supabaseClient)
        self.localStorageService = LocalStorageService()
        self.supabaseService = SupabaseService(client: supabaseClient)
        self.syncService = SyncService()
        self.validationService = ValidationService()
        self.geminiService = GeminiService()
        self.workoutStatsService = WorkoutStatsService(localStorage: localStorageService)

        self.profileRepository = ProfileRepository(
            localStorage: localStorageService,
            supabaseService: supabaseService
        )
        self.workoutRepository = WorkoutRepository(
            localStorage: localStorageService,
            supabaseService: supabaseService
        )
        self.prRepository = PRRepository(
            localStorage: localStorageService,
            supabaseService: supabaseService
        )
        self.monthPlanRepository = MonthPlanRepository(
            localStorage: localStorageService,
            supabaseService: supabaseService
        )

        self.coachPromptService = CoachPromptService(validationService: validationService)
        self.coachContextBuilder = CoachContextBuilder(
            profileRepository: profileRepository,
            workoutRepository: workoutRepository,
            localStorage: localStorageService,
            validationService: validationService
        )

        self.workoutSessionService = WorkoutSessionService(
            geminiService: geminiService,
            coachPromptService: coachPromptService,
            coachContextBuilder: coachContextBuilder,
            workoutRepository: workoutRepository,
            monthPlanRepository: monthPlanRepository,
            localStorage: localStorageService,
            supabaseService: supabaseService,
            validationService: validationService
        )

        self.monthPlanService = MonthPlanService(
            geminiService: GeminiService(), // Separate instance to avoid delegate conflicts
            coachPromptService: coachPromptService,
            coachContextBuilder: coachContextBuilder,
            monthPlanRepository: monthPlanRepository,
            validationService: validationService
        )

        authService.delegate = self
        checkExistingSession()
        loadOnboardingState()
    }

    // MARK: - Factory Methods

    func makeTodayViewModel() -> TodayViewModel {
        TodayViewModel(
            sessionService: workoutSessionService,
            workoutRepository: workoutRepository,
            prRepository: prRepository
        )
    }

    func makeWorkoutSetupViewModel() -> WorkoutSetupViewModel {
        WorkoutSetupViewModel(
            profileRepository: profileRepository,
            validationService: validationService
        )
    }

    func makeActiveWorkoutViewModel() -> ActiveWorkoutViewModel {
        ActiveWorkoutViewModel()
    }

    func makeProfileViewModel() -> ProfileViewModel {
        ProfileViewModel(
            workoutRepository: workoutRepository,
            statsService: workoutStatsService,
            profileRepository: profileRepository,
            prRepository: prRepository,
            validationService: validationService
        )
    }

    func makeHistoryViewModel() -> HistoryViewModel {
        HistoryViewModel(
            workoutRepository: workoutRepository
        )
    }

    func makeCoachChatViewModel() -> CoachChatViewModel {
        CoachChatViewModel(
            geminiService: GeminiService(), // Separate instance for chat
            coachPromptService: coachPromptService,
            coachContextBuilder: coachContextBuilder,
            validationService: validationService
        )
    }

    func makeMonthPlanViewModel() -> MonthPlanViewModel {
        MonthPlanViewModel(monthPlanRepository: monthPlanRepository)
    }

    func makePlanBuilderViewModel() -> PlanBuilderViewModel {
        let vm = PlanBuilderViewModel(
            monthPlanService: monthPlanService,
            validationService: validationService
        )
        if let userId = authService.currentUser()?.userId {
            vm.setUserId(userId)
        }
        return vm
    }

    // MARK: - AuthServiceDelegate

    func authServiceDidSignIn(_ service: AuthService) {
        needsEmailVerification = false
        pendingVerificationEmail = nil
        pendingVerificationPassword = nil
        isAuthenticated = true
    }

    func authServiceDidSignOut(_ service: AuthService) {
        isAuthenticated = false
        hasCompletedOnboarding = false
        needsEmailVerification = false
        pendingVerificationEmail = nil
        pendingVerificationPassword = nil
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    }

    func authServiceNeedsEmailVerification(_ service: AuthService, email: String) {
        pendingVerificationEmail = email
        needsEmailVerification = true
        isAuthenticated = false
    }

    func authService(_ service: AuthService, didFailWith error: Error) {
        authErrorMessage = error.localizedDescription
    }

    // MARK: - Private

    private func checkExistingSession() {
        isAuthenticated = authService.currentUser() != nil
    }

    private func loadOnboardingState() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }
}
