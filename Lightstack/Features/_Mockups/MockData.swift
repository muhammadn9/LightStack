import Foundation

/// Static dummy data used by the V3 mockup previews. Self-contained — does not
/// touch real models or repositories so previews work without any app state.
enum MockData {

    // MARK: - Today

    static let todayWorkoutType = "Push Day"

    static let todayExercises: [MockExercise] = [
        MockExercise(name: "Barbell Bench Press", muscleGroup: "Chest",      targetSets: 4, targetReps: "6-8",  targetRir: "2", restSec: 120),
        MockExercise(name: "Incline DB Press",    muscleGroup: "Chest",      targetSets: 3, targetReps: "8-10", targetRir: "2", restSec: 90),
        MockExercise(name: "Overhead Press",      muscleGroup: "Shoulders",  targetSets: 3, targetReps: "6-8",  targetRir: "2", restSec: 120),
        MockExercise(name: "Lateral Raises",      muscleGroup: "Shoulders",  targetSets: 3, targetReps: "12-15", targetRir: "1", restSec: 60),
        MockExercise(name: "Tricep Pushdown",     muscleGroup: "Triceps",    targetSets: 3, targetReps: "10-12", targetRir: "1", restSec: 60),
    ]

    static let activeLoggedSets: [MockSet] = [
        MockSet(setNumber: 1, weightLbs: 135, reps: 8, rir: 3),
        MockSet(setNumber: 2, weightLbs: 155, reps: 7, rir: 2),
        MockSet(setNumber: 3, weightLbs: 165, reps: 6, rir: 2),
    ]

    // MARK: - Plan

    static let monthSessions: [MockPlannedSession] = {
        let cal = Calendar.current
        let today = Date()
        return (0..<28).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: offset - 14, to: today) else { return nil }
            let dow = cal.component(.weekday, from: date)
            if dow == 1 || dow == 7 { return MockPlannedSession(date: date, type: "Rest", isCompleted: false, isRest: true) }
            let types = ["Push Day", "Pull Day", "Legs", "Upper", "Lower"]
            let type = types[abs(dow) % types.count]
            let isPast = date < cal.startOfDay(for: today)
            return MockPlannedSession(date: date, type: type, isCompleted: isPast && (dow % 3 != 0), isRest: false)
        }
    }()

    // MARK: - Log / History

    static let history: [MockHistoryEntry] = [
        MockHistoryEntry(date: daysAgo(1),  workoutType: "Push Day", durationMinutes: 58, totalVolumeLbs: 12_450, exerciseCount: 5, prCount: 1),
        MockHistoryEntry(date: daysAgo(3),  workoutType: "Pull Day", durationMinutes: 51, totalVolumeLbs: 11_200, exerciseCount: 5, prCount: 0),
        MockHistoryEntry(date: daysAgo(5),  workoutType: "Legs",     durationMinutes: 67, totalVolumeLbs: 18_900, exerciseCount: 6, prCount: 2),
        MockHistoryEntry(date: daysAgo(8),  workoutType: "Push Day", durationMinutes: 55, totalVolumeLbs: 11_800, exerciseCount: 5, prCount: 0),
        MockHistoryEntry(date: daysAgo(10), workoutType: "Pull Day", durationMinutes: 49, totalVolumeLbs: 10_750, exerciseCount: 5, prCount: 0),
    ]

    static let prs: [MockPR] = [
        MockPR(exerciseName: "Barbell Bench Press", weightLbs: 185, reps: 5, date: daysAgo(1)),
        MockPR(exerciseName: "Squat",                weightLbs: 275, reps: 3, date: daysAgo(5)),
        MockPR(exerciseName: "Deadlift",             weightLbs: 315, reps: 3, date: daysAgo(12)),
        MockPR(exerciseName: "Overhead Press",       weightLbs: 115, reps: 5, date: daysAgo(18)),
    ]

    // MARK: - Profile / Me

    static let userName = "Alex Carter"
    static let userEmail = "alex@example.com"
    static let userStreak = 12
    static let userTotalSessions = 84
    static let userTotalVolumeLbs: Double = 1_240_000
    static let userAvgSessionMin = 56

    static let muscleVolume: [(muscle: String, volume: Double)] = [
        ("Chest",     38_000),
        ("Back",      42_500),
        ("Legs",      71_200),
        ("Shoulders", 22_800),
        ("Arms",      18_500),
        ("Core",      9_400),
    ]

    // MARK: - AI Coach

    static let coachMessages: [MockCoachMessage] = [
        MockCoachMessage(role: .coach, text: "Nice job hitting 165 × 6 on bench. Want me to bump next set or keep it steady?"),
        MockCoachMessage(role: .user,  text: "Bump it slightly, I have one more in the tank."),
        MockCoachMessage(role: .coach, text: "Try 170 × 5 with 2 RIR. If it moves clean, we'll add a back-off set at 145."),
    ]

    static let coachSuggestions: [String] = [
        "Add a back-off set",
        "Swap to dumbbells",
        "I'm feeling tired",
        "Skip last set",
    ]

    // MARK: - Helpers

    private static func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date()
    }
}

// MARK: - Mock model structs

struct MockExercise: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let muscleGroup: String
    let targetSets: Int
    let targetReps: String
    let targetRir: String
    let restSec: Int
}

struct MockSet: Identifiable, Hashable {
    let id = UUID()
    let setNumber: Int
    let weightLbs: Double
    let reps: Int
    let rir: Int
}

struct MockPlannedSession: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let type: String
    let isCompleted: Bool
    let isRest: Bool
}

struct MockHistoryEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let workoutType: String
    let durationMinutes: Int
    let totalVolumeLbs: Double
    let exerciseCount: Int
    let prCount: Int
}

struct MockPR: Identifiable, Hashable {
    let id = UUID()
    let exerciseName: String
    let weightLbs: Double
    let reps: Int
    let date: Date
}

struct MockCoachMessage: Identifiable, Hashable {
    let id = UUID()
    enum Role { case user, coach }
    let role: Role
    let text: String
}
