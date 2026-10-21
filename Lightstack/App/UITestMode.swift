#if DEBUG
import Foundation
import os

/// Debug-only switch for the automated UI tests (compiled out of Release builds).
///
/// Launch arguments:
///  - `-uiTesting`       fixed signed-in test user, separate on-disk store, fake AI.
///  - `-uiTestingReset`  also wipes the test store and test session state, then reseeds.
enum UITestMode {
    static let isActive: Bool = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    /// `-uiTestingLiftHistory` adds weekly Bench Press history and a rest day for chart tests.
    /// `-uiTestingRearDeltHistory` adds two past "Rear Delt Fly Machine" sessions (newest has 3 distinct sets).
    static let wantsRearDeltHistory: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingRearDeltHistory")
    static let wantsLiftHistory: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingLiftHistory")
    /// `-uiTestingDuplicateNames` logs one lift under two spellings ("Leg Extension" / "Leg extension machine").
    static let wantsDuplicateNames: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingDuplicateNames")
    /// `-uiTestingPendingSyncOps N` seeds N unsynced operations for the test user (sign-out warning tests).
    static var pendingSyncOps: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiTestingPendingSyncOps"), i + 1 < args.count else { return 0 }
        return Int(args[i + 1]) ?? 0
    }
    /// `-uiTestingFakeRemote offline|online` replaces Supabase as the queue's remote and allows flushing.
    static var fakeRemoteMode: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiTestingFakeRemote"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    /// `-uiTestingSkipLaunchFlush` keeps the launch-time flush from running (foreground-trigger test).
    static let skipLaunchFlush: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingSkipLaunchFlush")
    /// `-uiTestingFreshInstall` seeds no local profile or history: the app starts like a new device.
    static let freshInstall: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingFreshInstall")
    /// `-uiTestingRemoteSeed history` fills the fake remote with a profile, workouts, a rest day and a tombstone.
    static var remoteSeed: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiTestingRemoteSeed"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    /// `-uiTestingRestoreDelay N` makes every fake remote read take N seconds (so the restore screen can be seen).
    static var restoreDelay: TimeInterval {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiTestingRestoreDelay"), i + 1 < args.count else { return 0 }
        return TimeInterval(args[i + 1]) ?? 0
    }
    static let shouldReset: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingReset")

    /// Constant id of the fake signed-in user.
    static let userId = UUID(uuid: (0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6, 0x47, 0x08,
                                    0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x01))

    static let sessionStateKey = "com.lightstack.activeWorkoutSession.uitests"
    private static let storeFileName = "Lightstack-UITests.sqlite"
    private static let logger = Logger(subsystem: "org.lightstack.app", category: "UITestMode")
    private static var didReset = false

    static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(storeFileName)
    }

    /// Called before the persistent store loads. Wipes test data once per process when asked.
    static func prepareStore() {
        guard isActive, shouldReset, !didReset else { return }
        didReset = true
        let url = storeURL
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: sessionStateKey)
        defaults.removeObject(forKey: RestPreference.key)
        defaults.removeObject(forKey: "lightstack_offline_queue_v1")
        defaults.removeObject(forKey: "lightstack.lastSuccessfulRestore.\(userId.uuidString)")
        defaults.set(0, forKey: "selectedTab")
        logger.debug("Reset UI test store")
    }

    /// The fake signed-in user returned by `AuthService.currentUser()`.
    static var testUser: UserProfile { makeProfile() }

    private static func makeProfile() -> UserProfile {
        UserProfile.create(
            userId: userId,
            displayName: "UI Tester",
            age: 30,
            heightInches: 70,
            weightLbs: 180,
            trainingAgeMonths: 24,
            primaryGoals: ["Strength"],
            splitDays: ["Push", "Pull", "Legs"],
            avoidExercises: [],
            equipment: ["Barbell": true, "Dumbbells": true],
            customEquipment: nil,
            notesToCoach: nil
        )
    }

    /// Writes the profile and one past Push workout when the store has no profile yet.
    static func seedIfNeeded(localStorage: LocalStorageService) {
        guard isActive, !freshInstall, localStorage.fetchProfile(userId: userId) == nil else { return }
        localStorage.saveProfile(makeProfile())

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        var workout = Workout.create(userId: userId, workoutType: "Push",
                                     energyLevel: 7, timeAvailableMinutes: 60)
        workout.date = yesterday
        workout.createdAt = yesterday
        // No duration: mimics an imported workout, which Avg Duration ignores.
        workout.syncStatus = .synced
        localStorage.saveWorkout(workout)

        let bench = Exercise.create(workoutId: workout.id, name: "Bench Press", muscleGroup: "Chest",
                                    orderIndex: 0, targetSets: 2, targetReps: "8", targetRir: "2",
                                    restSeconds: 90, coachNote: nil)
        let press = Exercise.create(workoutId: workout.id, name: "Overhead Press", muscleGroup: "Shoulders",
                                    orderIndex: 1, targetSets: 2, targetReps: "8", targetRir: "2",
                                    restSeconds: 90, coachNote: nil)
        localStorage.saveExercises([bench, press], workoutId: workout.id)

        let rows: [(Exercise, [(Double, Int, Int)])] = [
            (bench, [(135, 8, 2), (135, 7, 1)]),
            (press, [(85, 8, 2), (85, 6, 1)])
        ]
        seedSets(rows, localStorage: localStorage)

        // An imported-style workout whose name is not a split day ("From history").
        let earlier = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        var armDay = Workout.create(userId: userId, workoutType: "Arm Day",
                                    energyLevel: 7, timeAvailableMinutes: 45)
        armDay.date = earlier
        armDay.createdAt = earlier
        armDay.syncStatus = .synced
        localStorage.saveWorkout(armDay)
        let curl = Exercise.create(workoutId: armDay.id, name: "Barbell Curl", muscleGroup: "Biceps",
                                   orderIndex: 0, targetSets: 2, targetReps: "10", targetRir: "2",
                                   restSeconds: 60, coachNote: nil)
        let skull = Exercise.create(workoutId: armDay.id, name: "Skull Crusher", muscleGroup: "Triceps",
                                    orderIndex: 1, targetSets: 2, targetReps: "10", targetRir: "2",
                                    restSeconds: 60, coachNote: nil)
        localStorage.saveExercises([curl, skull], workoutId: armDay.id)
        seedSets([(curl, [(65, 10, 2), (65, 9, 1)]), (skull, [(55, 10, 2), (55, 9, 1)])],
                 localStorage: localStorage)

        // Dated today so the current week always has equipment usage (cable + machine).
        let now = Date()
        var core = Workout.create(userId: userId, workoutType: "Core Day",
                                  energyLevel: 7, timeAvailableMinutes: 30)
        core.date = now
        core.createdAt = now
        core.syncStatus = .synced
        localStorage.saveWorkout(core)
        let pulldown = Exercise.create(workoutId: core.id, name: "Lat Pulldown", muscleGroup: "Back",
                                       orderIndex: 0, targetSets: 3, targetReps: "10", targetRir: "2",
                                       restSeconds: 60, coachNote: nil)
        let legPress = Exercise.create(workoutId: core.id, name: "Leg Press", muscleGroup: "Legs",
                                       orderIndex: 1, targetSets: 2, targetReps: "10", targetRir: "2",
                                       restSeconds: 60, coachNote: nil)
        localStorage.saveExercises([pulldown, legPress], workoutId: core.id)
        seedSets([(pulldown, [(100, 10, 2), (100, 10, 2), (100, 9, 1)]), (legPress, [(180, 10, 2), (180, 9, 1)])],
                 localStorage: localStorage)

        if wantsLiftHistory { seedLiftHistory(localStorage: localStorage) }
        if wantsRearDeltHistory { seedRearDeltHistory(localStorage: localStorage) }
        if wantsDuplicateNames {
            // Same lift under two spellings, added to existing seeded workouts.
            let legExt = Exercise.create(workoutId: armDay.id, name: "Leg Extension", muscleGroup: "Legs",
                                         orderIndex: 2, targetSets: 2, targetReps: "12", targetRir: "2",
                                         restSeconds: 60, coachNote: nil)
            localStorage.saveExercises([legExt], workoutId: armDay.id)
            seedSets([(legExt, [(90, 12, 2), (90, 11, 1)])], localStorage: localStorage)
            let legExtMachine = Exercise.create(workoutId: workout.id, name: "Leg extension machine", muscleGroup: "Legs",
                                                orderIndex: 2, targetSets: 2, targetReps: "12", targetRir: "2",
                                                restSeconds: 60, coachNote: nil)
            localStorage.saveExercises([legExtMachine], workoutId: workout.id)
            seedSets([(legExtMachine, [(110, 12, 2), (110, 10, 1)])], localStorage: localStorage)
        }

        seedPersonalRecords(localStorage: localStorage)
    }

    /// A real user's PRs already exist next to their sets (they are created as lifts are
    /// logged), so the Profile tab's PR rebuild finds nothing to change. Create them here
    /// into a throwaway queue, so the tests' pending-sync counts only reflect what they seed.
    private static func seedPersonalRecords(localStorage: LocalStorageService) {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("uitest-seed-queue-\(UUID().uuidString)", isDirectory: true)
        let queue = OfflineQueueManager(
            remote: UITestFakeRemote(online: false),
            directory: scratch,
            ownerProvider: { nil },
            autoFlush: false
        )
        PRRepository(localStorage: localStorage, offlineQueueManager: queue).recalculateAllPRs(userId: userId)
    }

    /// Six older weekly Bench Press sessions (progressing weight) and a rest day 5 days ago.
    private static func seedLiftHistory(localStorage: LocalStorageService) {
        let calendar = Calendar.current
        for weeksAgo in 2...7 {
            guard let day = calendar.date(byAdding: .day, value: -7 * weeksAgo - 1, to: Date()) else { continue }
            var workout = Workout.create(userId: userId, workoutType: "Push",
                                         energyLevel: 7, timeAvailableMinutes: 45)
            workout.date = day
            workout.createdAt = day
            workout.syncStatus = .synced
            localStorage.saveWorkout(workout)
            let bench = Exercise.create(workoutId: workout.id, name: "Bench Press", muscleGroup: "Chest",
                                        orderIndex: 0, targetSets: 2, targetReps: "8", targetRir: "2",
                                        restSeconds: 90, coachNote: nil)
            localStorage.saveExercises([bench], workoutId: workout.id)
            let weight = Double(105 + (8 - weeksAgo) * 5)
            seedSets([(bench, [(weight, 8, 2), (weight, 7, 1)])], localStorage: localStorage)
        }
        if let rest = calendar.date(byAdding: .day, value: -5, to: Date()) {
            localStorage.addRestDay(userId: userId, date: rest)
        }
    }

    /// An older and a newer session of the same accessory lift, under a workout type that is
    /// not today's ("Pull Day"), so only a name-based lookup can find them.
    private static func seedRearDeltHistory(localStorage: LocalStorageService) {
        let sessions: [(daysAgo: Int, sets: [(Double, Int, Int)])] = [
            (20, [(40, 12, 3), (40, 10, 2)]),
            (6, [(55, 15, 3), (60, 12, 2), (65, 9, 1)])
        ]
        for session in sessions {
            guard let day = Calendar.current.date(byAdding: .day, value: -session.daysAgo, to: Date()) else { continue }
            var workout = Workout.create(userId: userId, workoutType: "Pull Day",
                                         energyLevel: 7, timeAvailableMinutes: 45)
            workout.date = day
            workout.createdAt = day
            workout.syncStatus = .synced
            localStorage.saveWorkout(workout)
            let fly = Exercise.create(workoutId: workout.id, name: "Rear Delt Fly Machine", muscleGroup: "Shoulders",
                                      orderIndex: 0, targetSets: session.sets.count, targetReps: "12", targetRir: "2",
                                      restSeconds: 60, coachNote: nil)
            localStorage.saveExercises([fly], workoutId: workout.id)
            seedSets([(fly, session.sets)], localStorage: localStorage)
        }
    }

    private static func seedSets(_ rows: [(Exercise, [(Double, Int, Int)])], localStorage: LocalStorageService) {
        for (exercise, sets) in rows {
            for (index, entry) in sets.enumerated() {
                let set = WorkoutSet.create(exerciseId: exercise.id, setNumber: index + 1,
                                            weightLbs: entry.0, reps: entry.1, rir: entry.2)
                localStorage.saveSet(set, exerciseId: exercise.id)
            }
        }
    }
}

/// Stand-in for Supabase in the offline-queue UI tests. Never touches the network.
/// "offline" throws a transient network error on every call; "online" records and succeeds.
final class UITestFakeRemote: RemoteWriting, RemoteReading, @unchecked Sendable {
    private let online: Bool
    private let dataset: UITestRemoteDataset
    private let lock = NSLock()
    private var calls: [String] = []
    private static let logger = Logger(subsystem: "org.lightstack.app", category: "UITestFakeRemote")

    init(online: Bool) {
        self.online = online
        self.dataset = UITestMode.remoteSeed == "history" ? .history() : UITestRemoteDataset()
    }

    // MARK: Reads (RemoteReading)

    private var didDelay = false

    /// Only the first read waits (`-uiTestingRestoreDelay`), so the restore screen stays up long enough to see.
    private func read(_ name: String) async throws {
        lock.lock()
        calls.append(name)
        let delay = didDelay ? 0 : UITestMode.restoreDelay
        didDelay = true
        lock.unlock()
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        if !online { throw URLError(.notConnectedToInternet) }
    }

    func fetchProfile(userId: UUID) async throws -> UserProfile? {
        try await read("fetchProfile")
        return dataset.profile
    }
    func fetchWorkoutHistoryPage(userId: UUID, offset: Int, limit: Int) async throws -> [RemoteWorkoutRecord] {
        try await read("fetchWorkoutHistoryPage")
        return Array(dataset.workouts.dropFirst(offset).prefix(limit))
    }
    func fetchContextSummaries(userId: UUID) async throws -> [AIContextSummary] {
        try await read("fetchContextSummaries")
        return []
    }
    func fetchActiveMonthPlan(userId: UUID) async throws -> MonthPlan? {
        try await read("fetchActiveMonthPlan")
        return nil
    }
    func fetchPlannedSessions(monthPlanId: UUID) async throws -> [PlannedSession] {
        try await read("fetchPlannedSessions")
        return []
    }
    func fetchRestDays(userId: UUID) async throws -> [RestDay] {
        try await read("fetchRestDays")
        return dataset.restDays
    }
    func fetchTombstones(userId: UUID) async throws -> [RemoteTombstone] {
        try await read("fetchTombstones")
        return dataset.tombstones
    }

    // MARK: Writes (RemoteWriting)

    private func record(_ name: String) throws {
        lock.lock(); calls.append(name); lock.unlock()
        Self.logger.debug("fake remote \(name, privacy: .public) online=\(self.online)")
        if !online { throw URLError(.notConnectedToInternet) }
    }

    func insertWorkout(_ workout: Workout) async throws { try record("insertWorkout") }
    func updateWorkout(_ workout: Workout) async throws { try record("updateWorkout") }
    func deleteWorkout(workoutId: UUID) async throws { try record("deleteWorkout") }
    func deleteSet(setId: UUID) async throws { try record("deleteSet") }
    func deleteExercise(id: UUID) async throws { try record("deleteExercise") }
    func deleteExercises(workoutId: UUID) async throws { try record("deleteExercises") }
    func insertExercises(_ exercises: [Exercise]) async throws { try record("insertExercises") }
    func insertSet(_ workoutSet: WorkoutSet) async throws { try record("insertSet") }
    func updateExerciseNames(ids: [UUID], name: String) async throws { try record("updateExerciseNames") }
    func upsertProfile(_ profile: UserProfile) async throws { try record("upsertProfile") }
    func insertPersonalRecord(_ record: PersonalRecord) async throws { try self.record("insertPersonalRecord") }
    func upsertContextSummary(_ summary: AIContextSummary) async throws { try record("upsertContextSummary") }
    func insertMonthPlan(_ plan: MonthPlan) async throws { try record("insertMonthPlan") }
    func insertPlannedSessions(_ sessions: [PlannedSession]) async throws { try record("insertPlannedSessions") }
    func updatePlannedSession(_ session: PlannedSession) async throws { try record("updatePlannedSession") }
    func deleteMonthPlan(planId: UUID) async throws { try record("deleteMonthPlan") }
    func upsertRestDay(_ restDay: RestDay) async throws { try record("upsertRestDay") }
    func deleteRestDay(userId: UUID, date: Date) async throws { try record("deleteRestDay") }
    func insertTombstones(userId: UUID, entity: String, recordIds: [UUID], deletedAt: Date) async throws { try record("insertTombstones") }
}

/// What the fake remote "has in the cloud" for restore UI tests.
struct UITestRemoteDataset {
    var profile: UserProfile?
    var workouts: [RemoteWorkoutRecord] = []
    var restDays: [RestDay] = []
    var tombstones: [RemoteTombstone] = []

    /// A restored-looking account: profile, three worked sessions, a rest day, a workout that was
    /// deleted on another device (still in the cloud, but tombstoned) and an empty one (never restored).
    static func history() -> UITestRemoteDataset {
        let user = UITestMode.userId
        let calendar = Calendar.current
        func daysAgo(_ n: Int) -> Date {
            let base = calendar.date(byAdding: .day, value: -n, to: Date()) ?? Date()
            return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: base) ?? base
        }
        func record(_ type: String, daysAgo n: Int, lifts: [(String, String, Double)]) -> RemoteWorkoutRecord {
            var workout = Workout.create(userId: user, workoutType: type, energyLevel: 7, timeAvailableMinutes: 60)
            workout.date = daysAgo(n)
            workout.createdAt = daysAgo(n)
            workout.durationMinutes = 45
            workout.syncStatus = .synced
            let exercises: [(Exercise, [WorkoutSet])] = lifts.enumerated().map { index, lift in
                let exercise = Exercise.create(workoutId: workout.id, name: lift.0, muscleGroup: lift.1,
                                               orderIndex: index, targetSets: 2, targetReps: "8", targetRir: "2",
                                               restSeconds: 90, coachNote: nil)
                let sets = (1...2).map {
                    WorkoutSet.create(exerciseId: exercise.id, setNumber: $0, weightLbs: lift.2, reps: 8, rir: 2)
                }
                return (exercise, sets)
            }
            return RemoteWorkoutRecord(workout: workout, exercises: exercises)
        }

        var data = UITestRemoteDataset()
        data.profile = UserProfile.create(
            userId: user, displayName: "Restored Tester", age: 31, heightInches: 71, weightLbs: 185,
            trainingAgeMonths: 36, primaryGoals: ["Strength"], splitDays: ["Push", "Pull", "Legs"],
            avoidExercises: ["Behind Neck Press"], equipment: ["Barbell": true, "Dumbbells": true],
            customEquipment: nil, notesToCoach: "Careful with my left shoulder"
        )
        let ghost = record("Ghost Workout", daysAgo: 3, lifts: [("Bench Press", "Chest", 135)])
        data.workouts = [
            record("Restored Push", daysAgo: 1, lifts: [("Bench Press", "Chest", 155), ("Overhead Press", "Shoulders", 95)]),
            record("Restored Pull", daysAgo: 2, lifts: [("Barbell Row", "Back", 135)]),
            ghost,
            record("Restored Legs", daysAgo: 4, lifts: [("Back Squat", "Legs", 225)]),
            RemoteWorkoutRecord(
                workout: {
                    var empty = Workout.create(userId: user, workoutType: "Empty Junk", energyLevel: nil, timeAvailableMinutes: nil)
                    empty.date = daysAgo(5)
                    empty.createdAt = daysAgo(5)
                    return empty
                }(),
                exercises: []
            )
        ]
        data.restDays = [RestDay(id: UUID(), userId: user, date: daysAgo(6).startOfDay, createdAt: daysAgo(6))]
        data.tombstones = [RemoteTombstone(entity: .workout, recordId: ghost.workout.id)]
        return data
    }
}

/// Canned AI provider used instead of Gemini while UI testing. Never touches the network.
final class UITestFakeAIProvider: AIProvider {
    let name = "UITestFake"
    let rateLimitKey = "uitest_fake_rate_limit"
    var isAvailable: Bool { true }
    var nextAvailableTime: Date? { nil }

    func markRateLimited(until: Date) {}
    func clearRateLimit() {}

    func generateChat(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        generateChat(systemPrompt: systemPrompt, messages: messages, expectsJSON: expectsJSON,
                     options: .default, completion: completion)
    }

    func generateChat(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool,
        options: AIRequestOptions,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let last = messages.last?.content ?? ""
        let reply: String
        if last.contains("completed sets") {
            // The merged post-workout call: progression note + rolling summary.
            reply = Self.postWorkoutJSON
        } else if expectsJSON {
            reply = Self.planJSON
        } else if last.lowercased().contains("heavier bench") {
            // Uses a shorter name than the workout's "Barbell Bench Press", like the real model does.
            reply = Self.benchModificationReply
        } else {
            reply = "Sounds good. Keep your reps smooth and stop each set with a couple in reserve."
        }
        DispatchQueue.main.async { completion(.success(reply)) }
    }

    static let postWorkoutJSON = """
    {"note": "Solid session. Everything moved well, so add 5 lbs to the first lift next time.",
     "summary": "Steady push session with all target weights hit. Add a little load next time."}
    """

    static let benchModificationReply = """
    Bumping bench to 155 for 10.

    ```json
    {"modifications": [{"action": "modify", "name": "Bench Press", "new_target_weight": "155 lbs", "new_target_reps": "10"}]}
    ```
    """

    static let planJSON = """
    {
      "coaching_notes": "Focus on controlled reps today.",
      "exercises": [
        {"name": "Barbell Bench Press", "muscle_group": "Chest", "sets": 3,
         "target_weight": "135 lbs", "reps": "8", "rir": "2", "rest_seconds": 90},
        {"name": "Incline Dumbbell Press", "muscle_group": "Chest", "sets": 3,
         "target_weight": "50 lbs", "reps": "10", "rir": "2", "rest_seconds": 90},
        {"name": "Cable Triceps Pushdown", "muscle_group": "Triceps", "sets": 3,
         "target_weight": "40 lbs", "reps": "12", "rir": "1", "rest_seconds": 60,
         "set_targets": [{"weight": "185", "reps": "8", "rir": "4"},
                         {"weight": "185", "reps": "8", "rir": "3"},
                         {"weight": "195", "reps": "6", "rir": "2"}]}
      ]
    }
    """
}

extension UITestMode {
    /// Resets the test queue on `-uiTestingReset`, then seeds `-uiTestingPendingSyncOps` harmless ops.
    static func prepareQueue(_ queue: OfflineQueueManager) async {
        if shouldReset { await queue.clearQueue() }
        for i in 0..<pendingSyncOps {
            let workout = Workout.create(userId: userId, workoutType: "Pending \(i)",
                                         energyLevel: nil, timeAvailableMinutes: nil)
            await queue.enqueue(.insertWorkout, payload: workout)
        }
    }
}
#endif
