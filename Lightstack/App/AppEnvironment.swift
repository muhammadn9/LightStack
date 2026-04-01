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

    /// The verification password is stored in the Keychain rather than as a
    /// plain property, so it never appears in memory dumps, crash reports,
    /// or SwiftUI state observation. The setter writes to / deletes from the
    /// Keychain; the getter reads from it on demand.
    var pendingVerificationPassword: String? {
        get { KeychainService.load(key: "pending_verification_password") }
        set {
            if let value = newValue {
                KeychainService.save(key: "pending_verification_password", value: value)
            } else {
                KeychainService.delete(key: "pending_verification_password")
            }
        }
    }

    // MARK: - Shared Client

    let supabaseClient: SupabaseClient

    // MARK: - Services

    let authService: AuthService
    let supabaseService: SupabaseService
    let localStorageService: LocalStorageService
    let offlineQueueManager: OfflineQueueManager
    let syncService: SyncService
    let validationService: ValidationService
    let aiServiceManager: AIServiceManager
    let geminiService: GeminiService  // Keep for backward compatibility
    let coachPromptService: CoachPromptService
    let workoutStatsService: WorkoutStatsService
    let sessionPersistence: WorkoutSessionPersistence

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

    @MainActor
    init() {
        let supabaseURL = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
        let supabaseKey = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""

        // Fail loudly at development time if keys are missing so misconfiguration
        // is never silently swallowed (placeholder URL would produce cryptic errors).
        assert(!supabaseURL.isEmpty, "SUPABASE_URL is not configured — add Secrets.xcconfig")
        assert(!supabaseKey.isEmpty, "SUPABASE_ANON_KEY is not configured — add Secrets.xcconfig")

        let resolvedURL = URL(string: supabaseURL) ?? URL(string: "https://placeholder.supabase.co")!
        self.supabaseClient = SupabaseClient(
            supabaseURL: resolvedURL,
            supabaseKey: supabaseKey,
            options: .init(
                auth: .init(
                    redirectToURL: AuthService.redirectURL
                )
            )
        )

        self.authService = AuthService(client: supabaseClient)
        self.localStorageService = LocalStorageService()
        self.supabaseService = SupabaseService(client: supabaseClient)
        self.offlineQueueManager = OfflineQueueManager(supabaseService: supabaseService)
        self.syncService = SyncService(offlineQueueManager: offlineQueueManager)
        self.validationService = ValidationService()

        // Initialize AI providers (priority order: Gemini → OpenAI → Claude)
        self.geminiService = GeminiService()
        let openAIService = OpenAIService()
        let claudeService = ClaudeService()
        self.aiServiceManager = AIServiceManager(providers: [geminiService, openAIService, claudeService])

        self.workoutStatsService = WorkoutStatsService(localStorage: localStorageService)
        self.sessionPersistence = WorkoutSessionPersistence()

        self.profileRepository = ProfileRepository(
            localStorage: localStorageService,
            supabaseService: supabaseService,
            offlineQueueManager: offlineQueueManager
        )
        self.workoutRepository = WorkoutRepository(
            localStorage: localStorageService,
            supabaseService: supabaseService,
            offlineQueueManager: offlineQueueManager
        )
        self.prRepository = PRRepository(
            localStorage: localStorageService,
            supabaseService: supabaseService,
            offlineQueueManager: offlineQueueManager
        )
        self.monthPlanRepository = MonthPlanRepository(
            localStorage: localStorageService,
            supabaseService: supabaseService,
            offlineQueueManager: offlineQueueManager
        )

        self.coachPromptService = CoachPromptService(validationService: validationService)
        self.coachContextBuilder = CoachContextBuilder(
            profileRepository: profileRepository,
            workoutRepository: workoutRepository,
            localStorage: localStorageService,
            validationService: validationService
        )

        self.workoutSessionService = WorkoutSessionService(
            aiServiceManager: aiServiceManager,
            coachPromptService: coachPromptService,
            coachContextBuilder: coachContextBuilder,
            workoutRepository: workoutRepository,
            monthPlanRepository: monthPlanRepository,
            localStorage: localStorageService,
            supabaseService: supabaseService,
            validationService: validationService,
            offlineQueueManager: offlineQueueManager
        )

        self.monthPlanService = MonthPlanService(
            aiServiceManager: aiServiceManager,
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
            prRepository: prRepository,
            sessionPersistence: sessionPersistence
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
            aiServiceManager: aiServiceManager,
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

        // Check if profile exists in database - if so, skip onboarding
        if let userId = authService.currentUser()?.userId {
            let profile = profileRepository.fetchProfileSync(userId: userId)
            if profile != nil {
                hasCompletedOnboarding = true
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            } else {
                hasCompletedOnboarding = false
            }
        }

        Task { @MainActor in
            syncService.triggerFlush()
        }
    }

    func authServiceDidSignOut(_ service: AuthService) {
        isAuthenticated = false
        hasCompletedOnboarding = false
        needsEmailVerification = false
        pendingVerificationEmail = nil
        pendingVerificationPassword = nil
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        // Clear queued writes so a future session (or different user) does not
        // flush stale operations under the wrong JWT.
        Task { await offlineQueueManager.clearQueue() }
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

        // If authenticated, verify profile exists in database
        if isAuthenticated, let userId = authService.currentUser()?.userId {
            let profile = profileRepository.fetchProfileSync(userId: userId)
            if profile != nil {
                print("[AppEnvironment] Existing profile found, setting hasCompletedOnboarding = true")
                hasCompletedOnboarding = true
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            } else {
                print("[AppEnvironment] No profile found, user needs onboarding")
                hasCompletedOnboarding = false
            }
        }
    }

    private func loadOnboardingState() {
        // loadOnboardingState is now handled in checkExistingSession
        // to ensure it's based on actual profile data, not just UserDefaults
    }
}
