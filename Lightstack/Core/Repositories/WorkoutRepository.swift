import Foundation

/// Coordinates local + remote workout data access.
/// Reads from Core Data for instant display, writes to both
/// Core Data and Supabase (via sync queue when offline).
final class WorkoutRepository {

    private let localStorage: LocalStorageService
    private let supabaseService: SupabaseService

    init(localStorage: LocalStorageService, supabaseService: SupabaseService) {
        self.localStorage = localStorage
        self.supabaseService = supabaseService
    }

    // MARK: - Fetch

    func fetchTodayWorkout(userId: UUID) -> Workout? {
        let cdWorkouts = localStorage.fetchWorkoutsForDate(userId: userId, date: Date())
        return cdWorkouts.first.map { Workout(from: $0) }
    }

    func fetchRecentWorkouts(userId: UUID, limit: Int) -> [Workout] {
        localStorage.fetchRecentWorkouts(userId: userId, limit: limit)
            .map { Workout(from: $0) }
    }

    // MARK: - Create / Save

    func createWorkout(_ workout: Workout) {
        localStorage.saveWorkout(workout)
        Task {
            do {
                try await supabaseService.insertWorkout(workout)
            } catch {
                print("WorkoutRepository: Supabase insert failed: \(error.localizedDescription)")
            }
        }
    }

    func saveExercises(_ exercises: [Exercise], workoutId: UUID) {
        localStorage.saveExercises(exercises, workoutId: workoutId)
        Task {
            do {
                try await supabaseService.insertExercises(exercises)
            } catch {
                print("WorkoutRepository: Supabase exercises insert failed: \(error.localizedDescription)")
            }
        }
    }

    func saveSet(_ workoutSet: WorkoutSet, exerciseId: UUID) {
        localStorage.saveSet(workoutSet, exerciseId: exerciseId)
        Task {
            do {
                try await supabaseService.insertSet(workoutSet)
            } catch {
                print("WorkoutRepository: Supabase set insert failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Update

    func updateWorkout(_ workout: Workout) {
        localStorage.updateWorkout(workout)
        Task {
            do {
                try await supabaseService.updateWorkout(workout)
            } catch {
                print("WorkoutRepository: Supabase update failed: \(error.localizedDescription)")
            }
        }
    }

    func updateSet(_ workoutSet: WorkoutSet) {
        localStorage.updateSet(workoutSet)
        // Note: Supabase doesn't have an updateSet method, PR flag is saved on initial insert
    }

    // MARK: - Streak

    func fetchStreak(userId: UUID) -> Int {
        // Try Supabase view first, fallback to local calculation
        var streak = localStorage.countConsecutiveWorkoutDays(userId: userId)
        Task {
            do {
                let remoteStreak = try await supabaseService.fetchCurrentStreak(userId: userId)
                if remoteStreak > streak {
                    streak = remoteStreak
                }
            } catch {
                // Local calculation is the fallback
            }
        }
        return streak
    }

    // MARK: - Fetch Exercises/Sets (for post-workout)

    func fetchExercises(workoutId: UUID) -> [Exercise] {
        localStorage.fetchExercises(workoutId: workoutId)
            .map { Exercise(from: $0) }
    }

    func fetchSets(exerciseId: UUID) -> [WorkoutSet] {
        localStorage.fetchSets(exerciseId: exerciseId)
            .map { WorkoutSet(from: $0) }
    }
}
