import Foundation

/// Calculates detailed workout statistics from local Core Data.
final class WorkoutStatsService {

    private let localStorage: LocalStorageService

    init(localStorage: LocalStorageService) {
        self.localStorage = localStorage
    }

    // MARK: - Stats

    func totalSessions(userId: UUID) -> Int {
        localStorage.fetchRecentWorkouts(userId: userId, limit: 100000).count
    }

    func totalVolume(userId: UUID) -> Double {
        let workouts = localStorage.fetchRecentWorkouts(userId: userId, limit: 100000)
        var volume = 0.0
        for cdWorkout in workouts {
            let workout = Workout(from: cdWorkout)
            let exercises = localStorage.fetchExercises(workoutId: workout.id)
            for cdExercise in exercises {
                let sets = localStorage.fetchSets(exerciseId: cdExercise.id ?? UUID())
                for cdSet in sets {
                    volume += cdSet.weightLbs * Double(cdSet.reps)
                }
            }
        }
        return volume
    }

    func averageRIR(userId: UUID) -> Double {
        let workouts = localStorage.fetchRecentWorkouts(userId: userId, limit: 100000)
        var totalRir = 0.0
        var count = 0.0
        for cdWorkout in workouts {
            let workout = Workout(from: cdWorkout)
            let exercises = localStorage.fetchExercises(workoutId: workout.id)
            for cdExercise in exercises {
                let sets = localStorage.fetchSets(exerciseId: cdExercise.id ?? UUID())
                for cdSet in sets {
                    totalRir += Double(cdSet.rir)
                    count += 1
                }
            }
        }
        return count > 0 ? totalRir / count : 0
    }

    func setsPerMuscleGroup(userId: UUID) -> [String: Int] {
        let workouts = localStorage.fetchRecentWorkouts(userId: userId, limit: 100000)
        var result: [String: Int] = [:]
        for cdWorkout in workouts {
            let workout = Workout(from: cdWorkout)
            let exercises = localStorage.fetchExercises(workoutId: workout.id)
            for cdExercise in exercises {
                let group = cdExercise.muscleGroup ?? "Unknown"
                let setCount = localStorage.fetchSets(exerciseId: cdExercise.id ?? UUID()).count
                result[group, default: 0] += setCount
            }
        }
        return result
    }

    func volumePerMuscleGroup(userId: UUID) -> [String: Double] {
        let workouts = localStorage.fetchRecentWorkouts(userId: userId, limit: 100000)
        var result: [String: Double] = [:]
        for cdWorkout in workouts {
            let workout = Workout(from: cdWorkout)
            let exercises = localStorage.fetchExercises(workoutId: workout.id)
            for cdExercise in exercises {
                let group = cdExercise.muscleGroup ?? "Unknown"
                let sets = localStorage.fetchSets(exerciseId: cdExercise.id ?? UUID())
                for cdSet in sets {
                    let volume = cdSet.weightLbs * Double(cdSet.reps)
                    result[group, default: 0] += volume
                }
            }
        }
        return result
    }

    func weeklyFrequency(userId: UUID) -> Double {
        let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: Date()) ?? Date()
        let workouts = localStorage.fetchRecentWorkouts(userId: userId, limit: 100000)
        let recentCount = workouts.filter { ($0.date ?? Date.distantPast) >= fourWeeksAgo }.count
        return Double(recentCount) / 4.0
    }

    func averageSessionDuration(userId: UUID) -> Int {
        let workouts = localStorage.fetchRecentWorkouts(userId: userId, limit: 100000)
        let durations = workouts.compactMap { w -> Int? in
            let mins = Int(w.durationMinutes)
            return mins > 0 ? mins : nil
        }
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / durations.count
    }

    func estimatedOneRepMax(userId: UUID, exerciseName: String) -> Double? {
        let workouts = localStorage.fetchRecentWorkouts(userId: userId, limit: 100000)
        var bestE1RM = 0.0
        for cdWorkout in workouts {
            let workout = Workout(from: cdWorkout)
            let exercises = localStorage.fetchExercises(workoutId: workout.id)
            for cdExercise in exercises where cdExercise.name == exerciseName {
                let sets = localStorage.fetchSets(exerciseId: cdExercise.id ?? UUID())
                for cdSet in sets {
                    let weight = cdSet.weightLbs
                    let reps = Double(cdSet.reps)
                    guard weight > 0, reps > 0 else { continue }
                    let e1rm = weight * (1 + reps / 30)
                    bestE1RM = max(bestE1RM, e1rm)
                }
            }
        }
        return bestE1RM > 0 ? bestE1RM : nil
    }

    func topLifts(userId: UUID, limit: Int = 5) -> [(exerciseName: String, e1rm: Double)] {
        let workouts = localStorage.fetchRecentWorkouts(userId: userId, limit: 100000)
        var bestByExercise: [String: Double] = [:]
        for cdWorkout in workouts {
            let workout = Workout(from: cdWorkout)
            let exercises = localStorage.fetchExercises(workoutId: workout.id)
            for cdExercise in exercises {
                let name = cdExercise.name ?? "Unknown"
                let sets = localStorage.fetchSets(exerciseId: cdExercise.id ?? UUID())
                for cdSet in sets {
                    let weight = cdSet.weightLbs
                    let reps = Double(cdSet.reps)
                    guard weight > 0, reps > 0 else { continue }
                    let e1rm = weight * (1 + reps / 30)
                    bestByExercise[name] = max(bestByExercise[name] ?? 0, e1rm)
                }
            }
        }
        return bestByExercise
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (exerciseName: $0.key, e1rm: $0.value) }
    }

    func sessionVolume(exercises: [Exercise], loggedSets: [UUID: [WorkoutSet]]) -> Double {
        var volume = 0.0
        for exercise in exercises {
            for s in loggedSets[exercise.id] ?? [] {
                volume += s.weightLbs * Double(s.reps)
            }
        }
        return volume
    }
}
