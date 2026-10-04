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
        defaults.removeObject(forKey: "lightstack_offline_queue_v1")
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
        guard isActive, localStorage.fetchProfile(userId: userId) == nil else { return }
        localStorage.saveProfile(makeProfile())

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        var workout = Workout.create(userId: userId, workoutType: "Push",
                                     energyLevel: 7, timeAvailableMinutes: 60)
        workout.date = yesterday
        workout.createdAt = yesterday
        workout.durationMinutes = 45
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
        for (exercise, sets) in rows {
            for (index, entry) in sets.enumerated() {
                let set = WorkoutSet.create(exerciseId: exercise.id, setNumber: index + 1,
                                            weightLbs: entry.0, reps: entry.1, rir: entry.2)
                localStorage.saveSet(set, exerciseId: exercise.id)
            }
        }
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
        let last = messages.last?.content ?? ""
        let reply: String
        if expectsJSON {
            reply = Self.planJSON
        } else if last.contains("progression note") {
            reply = "Solid session. Everything moved well, so add 5 lbs to the first lift next time."
        } else if last.contains("rolling summary") {
            reply = "Steady push session with all target weights hit. Add a little load next time."
        } else {
            reply = "Sounds good. Keep your reps smooth and stop each set with a couple in reserve."
        }
        DispatchQueue.main.async { completion(.success(reply)) }
    }

    static let planJSON = """
    {
      "coaching_notes": "Focus on controlled reps today.",
      "exercises": [
        {"name": "Barbell Bench Press", "muscle_group": "Chest", "sets": 3,
         "target_weight": "135 lbs", "reps": "8", "rir": "2", "rest_seconds": 90},
        {"name": "Incline Dumbbell Press", "muscle_group": "Chest", "sets": 3,
         "target_weight": "50 lbs", "reps": "10", "rir": "2", "rest_seconds": 90},
        {"name": "Cable Triceps Pushdown", "muscle_group": "Triceps", "sets": 3,
         "target_weight": "40 lbs", "reps": "12", "rir": "1", "rest_seconds": 60}
      ]
    }
    """
}
#endif
