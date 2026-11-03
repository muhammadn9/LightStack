import Foundation
import SwiftUI
import Supabase
import os

/// DI container and shared environment object.
/// Owns all service and repository singletons.
/// Conforms to AuthServiceDelegate to propagate auth state changes.
final class AppEnvironment: ObservableObject, AuthServiceDelegate {

    private let logger = Logger(subsystem: "org.lightstack.app", category: "AppEnvironment")

    // MARK: - Auth State

    @Published var isAuthenticated: Bool = false
    @Published var hasCompletedOnboarding: Bool = false
    @Published var needsEmailVerification: Bool = false
    @Published var pendingVerificationEmail: String?
    @Published var authErrorMessage: String?
    /// `restoring` / `failed` while a new device or reinstall is looking for the account's
    /// profile before deciding whether to onboard (see `beginProfileRestore`).
    @Published var restoreGate: RestoreGate = .idle

    enum RestoreGate: Equatable {
        case idle
        case restoring
        case failed
    }

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
    let syncRestoreService: SyncRestoreService
    let dataHygieneService: DataHygieneService
    let sessionExpiry: SessionExpiryTracker
    @MainActor let backupStatus: BackupStatusModel

    // MARK: - Repositories

    let workoutRepository: WorkoutRepository
    let profileRepository: ProfileRepository
    let prRepository: PRRepository
    let exerciseMergeService: ExerciseMergeService
    let workoutTypeMergeService: WorkoutTypeMergeService
    let monthPlanRepository: MonthPlanRepository
    let restDayRepository: RestDayRepository
    let nutritionRepository: NutritionRepository

    // MARK: - AI + Session Services

    let coachContextBuilder: CoachContextBuilder
    let workoutSessionService: WorkoutSessionService
    let monthPlanService: MonthPlanService
    let notificationService: NotificationService

    private var restoreTask: Task<Void, Never>?
    /// Owners whose dead-lettered operations were already revived in this launch.
    private var revivedOwners = Set<UUID>()

    // MARK: - Init

    @MainActor
    init() {
        let supabaseURL = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
        let supabaseKey = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""

        precondition(!supabaseURL.isEmpty, "SUPABASE_URL is not configured — add Secrets.xcconfig")
        precondition(!supabaseKey.isEmpty, "SUPABASE_ANON_KEY is not configured — add Secrets.xcconfig")
        guard let resolvedURL = URL(string: supabaseURL) else {
            fatalError("SUPABASE_URL is invalid — add a valid URL in Secrets.xcconfig")
        }
        self.supabaseClient = SupabaseClient(
            supabaseURL: resolvedURL,
            supabaseKey: supabaseKey,
            options: .init(
                auth: .init(
                    redirectToURL: AuthService.redirectURL,
                    // PKCE: a callback link only completes sign-in if this app started
                    // the flow (it holds the code verifier), so another app that
                    // claims lightstack:// can't inject a session.
                    flowType: .pkce
                )
            )
        )

        let expiryTracker = SessionExpiryTracker()
        self.sessionExpiry = expiryTracker
        self.authService = AuthService(client: supabaseClient, expiry: expiryTracker)
        self.localStorageService = LocalStorageService()
        localStorageService.removeDuplicateExercises()
        #if DEBUG
        if UITestMode.isActive { UITestMode.seedIfNeeded(localStorage: localStorageService) }
        #endif
        self.supabaseService = SupabaseService(client: supabaseClient)
        let queueAuth = authService
        var queueRemote: RemoteWriting = supabaseService
        var remoteReader: RemoteReading = supabaseService
        // Writes upload right after they are queued. UI tests must never reach the
        // network, so they only auto-upload when a fake remote is standing in.
        var queueAutoFlush = true
        #if DEBUG
        if UITestMode.isActive { queueAutoFlush = UITestMode.fakeRemoteMode != nil }
        #endif
        #if DEBUG
        if UITestMode.isActive {
            // UI tests never reach the network: reads come from the fake too. Without
            // `-uiTestingFakeRemote` it is an offline fake that fails every call.
            let fake = UITestFakeRemote(online: UITestMode.fakeRemoteMode == "online")
            if UITestMode.fakeRemoteMode != nil { queueRemote = fake }
            remoteReader = fake
        }
        #endif
        self.offlineQueueManager = OfflineQueueManager(
            remote: queueRemote,
            directory: OfflineQueueManager.defaultDirectory(),
            ownerProvider: { await MainActor.run { queueAuth.currentUser()?.userId } },
            autoFlush: queueAutoFlush,
            localLookup: StorageParentLookup(storage: localStorageService)
        )
        self.syncService = SyncService(offlineQueueManager: offlineQueueManager)
        self.backupStatus = BackupStatusModel(queue: offlineQueueManager, expiry: expiryTracker)
        #if DEBUG
        if UITestMode.isActive {
            let queue = offlineQueueManager
            Task { await UITestMode.prepareQueue(queue) }
        }
        #endif
        self.validationService = ValidationService()

        // AI providers, tried in order: Gemini models reached through the ai-proxy
        // Edge Function. No AI keys ship in the app; the function holds the key and
        // enforces the per-user rate limit.
        let proxyURL = resolvedURL.appendingPathComponent("functions/v1/ai-proxy")
        let client = supabaseClient
        let accessToken: () async -> String? = { try? await client.auth.session.accessToken }
        self.geminiService = GeminiService(model: "gemini-3.5-flash", proxyURL: proxyURL,
                                           anonKey: supabaseKey, accessToken: accessToken)
        let geminiFallback = GeminiService(model: "gemini-2.5-flash", proxyURL: proxyURL,
                                           anonKey: supabaseKey, accessToken: accessToken)
        var providers: [AIProvider] = [geminiService, geminiFallback]
        #if DEBUG
        if UITestMode.isActive { providers = [UITestFakeAIProvider()] }
        #endif
        self.aiServiceManager = AIServiceManager(providers: providers)

        self.workoutStatsService = WorkoutStatsService(localStorage: localStorageService)
        self.sessionPersistence = WorkoutSessionPersistence()

        self.profileRepository = ProfileRepository(
            localStorage: localStorageService,
            supabaseService: supabaseService,
            offlineQueueManager: offlineQueueManager
        )
        self.workoutRepository = WorkoutRepository(
            localStorage: localStorageService,
            offlineQueueManager: offlineQueueManager
        )
        self.prRepository = PRRepository(
            localStorage: localStorageService,
            offlineQueueManager: offlineQueueManager
        )
        self.exerciseMergeService = ExerciseMergeService(
            localStorage: localStorageService,
            offlineQueueManager: offlineQueueManager,
            prRepository: prRepository
        )
        self.workoutTypeMergeService = WorkoutTypeMergeService(
            localStorage: localStorageService,
            offlineQueueManager: offlineQueueManager,
            profileRepository: profileRepository
        )
        self.monthPlanRepository = MonthPlanRepository(
            localStorage: localStorageService,
            supabaseService: supabaseService,
            offlineQueueManager: offlineQueueManager
        )

        self.restDayRepository = RestDayRepository(
            localStorage: localStorageService,
            offlineQueueManager: offlineQueueManager
        )
        self.nutritionRepository = NutritionRepository(
            localStorage: localStorageService,
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

        self.notificationService = NotificationService()

        let persistence = sessionPersistence
        let sessionService = workoutSessionService
        self.syncRestoreService = SyncRestoreService(
            remote: remoteReader,
            storage: localStorageService,
            queue: offlineQueueManager,
            prRepository: prRepository,
            currentUserId: { queueAuth.currentUser()?.userId },
            activeWorkoutIds: {
                // The workout being logged right now (live or saved for relaunch) is never touched.
                var ids = Set<UUID>()
                if let saved = persistence.restoreSession() { ids.insert(saved.workout.id) }
                if let current = sessionService.currentWorkout { ids.insert(current.id) }
                return ids
            }
        )

        self.dataHygieneService = DataHygieneService(
            localStorage: localStorageService,
            workoutRepository: workoutRepository,
            prRepository: prRepository,
            currentPendingId: { sessionService.currentWorkout?.id },
            protectedWorkoutIds: {
                var ids = Set<UUID>()
                if let saved = persistence.restoreSession() { ids.insert(saved.workout.id) }
                if let current = sessionService.currentWorkout { ids.insert(current.id) }
                return ids
            }
        )

        ExerciseFeedbackStore.shared.attach(reviewStore: workoutSessionService.reviewStore)
        authService.delegate = self
        backupStatus.onAuthFailure = { [weak self] in self?.handleOutboxAuthFailure() }
        authService.startObservingSession()
        #if DEBUG
        if !UITestMode.isActive { MetricKitCollector.shared.start() }
        #else
        MetricKitCollector.shared.start()
        #endif
        #if DEBUG
        if UITestMode.isActive { simulateExpiredSessionForUITest(UITestMode.wantsExpiredSession) }
        #endif
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

    /// Creates a TodayViewModel with its own WorkoutSessionService instance,
    /// used for inline workout flows (e.g., Month tab) to avoid delegate collision
    /// with the main Today tab's shared service.
    func makeInlineTodayViewModel() -> TodayViewModel {
        let freshService = WorkoutSessionService(
            aiServiceManager: aiServiceManager,
            coachPromptService: coachPromptService,
            coachContextBuilder: coachContextBuilder,
            workoutRepository: workoutRepository,
            monthPlanRepository: monthPlanRepository,
            localStorage: localStorageService,
            validationService: validationService,
            offlineQueueManager: offlineQueueManager
        )
        return TodayViewModel(
            sessionService: freshService,
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
            workoutRepository: workoutRepository,
            prRepository: prRepository
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

    @MainActor func makeNutritionViewModel() -> NutritionViewModel {
        NutritionViewModel(repository: nutritionRepository, userIdProvider: { [authService] in authService.currentUser()?.userId })
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

        if let userId = authService.currentUser()?.userId {
            switch sessionExpiry.handleSignIn(userId: userId) {
            case .resumed:
                logger.info("same user signed in again; resuming the outbox")
            case .differentUser:
                logger.info("a different user signed in; the previous user's changes stay queued under their own id")
            case .notExpired:
                break
            }
            Task { @MainActor in backupStatus.refresh() }
        }

        // A profile on this device skips onboarding. Without one this may be a new device or a
        // reinstall: look for the account's cloud profile before deciding to onboard.
        if let userId = authService.currentUser()?.userId {
            if profileRepository.fetchProfileSync(userId: userId) != nil {
                hasCompletedOnboarding = true
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            } else {
                hasCompletedOnboarding = false
                beginProfileRestore(userId: userId)
            }
        }

        Task { @MainActor in
            flushReviving()
            startBackgroundRestoreIfDue()
        }
    }

    func authServiceDidSignOut(_ service: AuthService) {
        isAuthenticated = false
        hasCompletedOnboarding = false
        needsEmailVerification = false
        pendingVerificationEmail = nil
        pendingVerificationPassword = nil
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        restoreTask?.cancel()
        restoreGate = .idle
        // The offline queue is deliberately kept: unsynced changes are tagged with
        // their owner and upload the next time that user signs in on this device.
    }

    func authServiceSessionExpired(_ service: AuthService, userId: UUID) {
        Task { @MainActor in backupStatus.refresh() }
    }

    func authServiceNeedsEmailVerification(_ service: AuthService, email: String) {
        pendingVerificationEmail = email
        needsEmailVerification = true
        isAuthenticated = false
    }

    func authService(_ service: AuthService, didFailWith error: Error) {
        authErrorMessage = error.localizedDescription
    }

    // MARK: - Expired session

    private var lastRefreshAttempt: Date?

    /// An upload pass stopped on an auth error. Try to refresh the session once (rate limited); if the
    /// refresh token is dead, record the expiry (banner) while keeping every queued change.
    @MainActor
    func handleOutboxAuthFailure() {
        backupStatus.refresh()
        #if DEBUG
        if UITestMode.isActive { return }
        #endif
        guard !sessionExpiry.isExpired else { return }
        if let last = lastRefreshAttempt, Date().timeIntervalSince(last) < 30 { return }
        lastRefreshAttempt = Date()
        let client = supabaseClient
        let auth = authService
        let userId = auth.currentUser()?.userId ?? UserDefaults.standard.string(forKey: AuthService.lastKnownUserKey).flatMap(UUID.init(uuidString:))
        Task { @MainActor [weak self] in
            do {
                _ = try await client.auth.refreshSession()
                self?.syncService.triggerFlush()
            } catch {
                guard SyncErrorClassifier.isSessionRejected(error), let userId else { return }
                auth.reportSessionExpired(userId: userId)
            }
        }
    }

    /// "Sign in" on the banner: show the login screen without deleting anything. Signing in as the same
    /// user resumes uploading; another user is handled by `authServiceDidSignIn`.
    @MainActor
    func beginReauthentication() {
        isAuthenticated = false
    }

    #if DEBUG
    @MainActor
    private func simulateExpiredSessionForUITest(_ expired: Bool) {
        if expired { sessionExpiry.markExpired(userId: UITestMode.userId) } else { sessionExpiry.clear() }
        backupStatus.refresh()
    }
    #endif

    // MARK: - Private

    @MainActor
    private func checkExistingSession() {
        isAuthenticated = authService.currentUser() != nil

        // Upload anything left over from the last run.
        var allowLaunchFlush = isAuthenticated
        #if DEBUG
        if UITestMode.isActive && (UITestMode.fakeRemoteMode == nil || UITestMode.skipLaunchFlush) {
            allowLaunchFlush = false
        }
        #endif
        if allowLaunchFlush {
            Task { @MainActor in flushReviving() }
        }

        // If authenticated, check this device for a profile; without one, look in the cloud first.
        if isAuthenticated, let userId = authService.currentUser()?.userId {
            let profile = profileRepository.fetchProfileSync(userId: userId)
            if profile != nil {
                logger.debug("Existing profile found, setting hasCompletedOnboarding = true")
                hasCompletedOnboarding = true
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                startBackgroundRestoreIfDue()
            } else {
                logger.debug("No local profile, checking the cloud before onboarding")
                hasCompletedOnboarding = false
                beginProfileRestore(userId: userId)
            }
        }
    }

    /// Flushes the outbox. Once per launch per user it first moves due dead-lettered operations back
    /// into the queue, so nothing stays stuck in the dead-letter list forever.
    @MainActor
    func flushReviving() {
        #if DEBUG
        if UITestMode.isActive && UITestMode.fakeRemoteMode == nil { return }
        #endif
        let manager = offlineQueueManager
        var revive = false
        if let userId = authService.currentUser()?.userId { revive = revivedOwners.insert(userId).inserted }
        Task {
            if revive { await manager.reviveDueFailedOperations() }
            await manager.flush()
        }
    }

    /// "Back up now": revives every dead-lettered change (so a fixed server-side problem is retried at once),
    /// flushes, and refreshes the status row when the flush has finished.
    @MainActor
    func backUpNow() {
        #if DEBUG
        if UITestMode.isActive && UITestMode.fakeRemoteMode == nil { backupStatus.refresh(); return }
        #endif
        let manager = offlineQueueManager
        let model = backupStatus
        Task {
            await manager.retryFailed()
            await manager.flush()
            await model.refreshNow()
        }
    }

    // MARK: - Restore

    /// Blocks on a full-screen "Restoring your history..." while the cloud profile is looked up:
    /// found -> saved locally, onboarding skipped, then the rest of the history is restored on the
    /// same screen (bounded; a slow or failed history restore just carries on in the background);
    /// none -> onboarding as usual; unreachable -> `.failed` (Retry / Set up as new).
    func beginProfileRestore(userId: UUID) {
        restoreTask?.cancel()
        restoreGate = .restoring
        let service = syncRestoreService
        restoreTask = Task { @MainActor [weak self] in
            let lookup = await service.lookUpAccountProfile(userId: userId)
            guard let self, !Task.isCancelled else { return }
            switch lookup {
            case .existing:
                self.completeOnboardingState()
                await self.restoreHistoryOnRestoreScreen(userId: userId)
                self.restoreGate = .idle
            case .new:
                self.hasCompletedOnboarding = false
                self.restoreGate = .idle
            case .unreachable:
                self.restoreGate = .failed
            case .cancelled:
                self.restoreGate = .idle
            }
        }
    }

    func retryProfileRestore() {
        guard let userId = authService.currentUser()?.userId else { return }
        beginProfileRestore(userId: userId)
    }

    /// "Set up as new" from the failed screen. Onboarding re-checks the cloud before it saves
    /// anything, so this can never overwrite an existing cloud profile.
    func continueWithoutRestore() {
        restoreTask?.cancel()
        hasCompletedOnboarding = false
        restoreGate = .idle
    }

    private func completeOnboardingState() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    @MainActor
    private func restoreHistoryOnRestoreScreen(userId: UUID) async {
        let service = syncRestoreService
        let full = Task { @MainActor in try await service.restoreAll(userId: userId, assumeFreshInstall: true) }
        let cutoff = Task { try? await Task.sleep(nanoseconds: 60_000_000_000); full.cancel() }
        _ = try? await full.value
        cutoff.cancel()
        runDataHygieneIfNeeded(userId: userId)
        syncService.triggerFlush()   // repair uploads, if any
    }

    /// Onboarding's last step. Looks in the cloud one more time: if the account already has a
    /// profile it is adopted (and the history restored) instead of being overwritten.
    @MainActor
    func finishOnboarding(with profile: UserProfile) async -> SyncRestoreService.NewProfileResult {
        let repository = profileRepository
        let result = await syncRestoreService.saveNewProfileUnlessAccountHasOne(profile) {
            repository.saveProfile($0)
        }
        switch result {
        case .saved:
            completeOnboardingState()
        case .adoptedExisting:
            completeOnboardingState()
            startBackgroundRestoreIfDue()
        case .couldNotVerify:
            break
        }
        return result
    }

    /// Quiet restore on launch and foreground: after the outbox flush, at most every 6 hours
    /// per user. No UI. Skipped while the blocking restore owns the profile step.
    @MainActor
    func startBackgroundRestoreIfDue() {
        guard isAuthenticated, hasCompletedOnboarding, restoreGate == .idle,
              let userId = authService.currentUser()?.userId,
              !syncRestoreService.isRunning else { return }
        #if DEBUG
        // UI tests only restore when a test asks for it with a seeded fake remote.
        if UITestMode.isActive && UITestMode.remoteSeed == nil { return }
        #endif
        guard syncRestoreService.isRestoreDue(userId: userId) else {
            // No restore needed; the one-time cleanup still runs once per install.
            runDataHygieneIfNeeded(userId: userId)
            return
        }
        let service = syncRestoreService
        let queue = offlineQueueManager
        Task { @MainActor [weak self] in
            await queue.flush()
            do {
                try await service.restoreAll(userId: userId)
            } catch {
                self?.logger.info("background restore stopped: \(String(describing: error), privacy: .public)")
            }
            // After restore/hydration, so duplicates that came back from the cloud are covered.
            self?.runDataHygieneIfNeeded(userId: userId)
            self?.syncService.triggerFlush()
        }
    }

    /// One-time cleanup of duplicate workouts, never-started plans and messy PRs (see
    /// `DataHygieneService`). Flagged per user and version; deletes go through the offline queue.
    @MainActor
    private func runDataHygieneIfNeeded(userId: UUID) {
        #if DEBUG
        if UITestMode.isActive { return }
        #endif
        guard authService.currentUser()?.userId == userId,
              dataHygieneService.runIfNeeded(userId: userId) != nil else { return }
        syncService.triggerFlush()
    }

    private func loadOnboardingState() {
        // loadOnboardingState is now handled in checkExistingSession
        // to ensure it's based on actual profile data, not just UserDefaults
    }
}
