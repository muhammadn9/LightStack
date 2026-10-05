import Foundation

/// Coordinates local + remote workout data access.
/// Reads from Core Data for instant display, writes to both
/// Core Data and Supabase (via sync queue when offline).
final class WorkoutRepository {

    private let localStorage: LocalStorageService
    private let supabaseService: SupabaseService
    private let offlineQueueManager: OfflineQueueManager

    init(
        localStorage: LocalStorageService,
        supabaseService: SupabaseService,
        offlineQueueManager: OfflineQueueManager
    ) {
        self.localStorage = localStorage
        self.supabaseService = supabaseService
        self.offlineQueueManager = offlineQueueManager
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

    /// Distinct exercise names the user has done before, most recently used first.
    func fetchDistinctExerciseNames(userId: UUID) -> [HistoryExercise] {
        HistoryExercise.distinct(localStorage.fetchExerciseHistory(userId: userId))
    }

    // MARK: - Create / Save

    func createWorkout(_ workout: Workout) {
        localStorage.saveWorkout(workout)
        Task {
            do {
                try await supabaseService.insertWorkout(workout)
            } catch {
                await offlineQueueManager.enqueue(.insertWorkout, payload: workout)
            }
        }
    }

    func saveExercises(_ exercises: [Exercise], workoutId: UUID) {
        localStorage.saveExercises(exercises, workoutId: workoutId)
        Task {
            do {
                try await supabaseService.insertExercises(exercises)
            } catch {
                await offlineQueueManager.enqueue(.insertExercises, payload: exercises)
            }
        }
    }

    func saveSet(_ workoutSet: WorkoutSet, exerciseId: UUID) {
        localStorage.saveSet(workoutSet, exerciseId: exerciseId)
        Task {
            do {
                try await supabaseService.insertSet(workoutSet)
            } catch {
                await offlineQueueManager.enqueue(.insertSet, payload: workoutSet)
            }
        }
    }

    /// Saves a fully-formed past workout. Everything is written locally first, then
    /// synced to Supabase strictly in order (workout, exercises, sets) in ONE task so
    /// foreign keys never fail. On the first failure the remaining items go to the
    /// offline queue in the same order, using the same kinds as the single-item methods.
    func importWorkout(_ workout: Workout, exercises: [Exercise], sets: [UUID: [WorkoutSet]]) {
        localStorage.saveWorkout(workout)
        localStorage.saveExercises(exercises, workoutId: workout.id)
        for exercise in exercises {
            for set in sets[exercise.id] ?? [] {
                localStorage.saveSet(set, exerciseId: exercise.id)
            }
        }

        let orderedSets = exercises.flatMap { sets[$0.id] ?? [] }
        Task {
            var failed = false

            do { try await supabaseService.insertWorkout(workout) } catch {
                failed = true
                await offlineQueueManager.enqueue(.insertWorkout, payload: workout)
            }

            if failed {
                await offlineQueueManager.enqueue(.insertExercises, payload: exercises)
            } else {
                do { try await supabaseService.insertExercises(exercises) } catch {
                    failed = true
                    await offlineQueueManager.enqueue(.insertExercises, payload: exercises)
                }
            }

            for set in orderedSets {
                if failed {
                    await offlineQueueManager.enqueue(.insertSet, payload: set)
                } else {
                    do { try await supabaseService.insertSet(set) } catch {
                        failed = true
                        await offlineQueueManager.enqueue(.insertSet, payload: set)
                    }
                }
            }
        }
    }

    /// Replaces a workout's header, exercises and sets (used by editing past workouts).
    /// Local: update workout, delete old exercises (sets cascade), save new exercises/sets.
    /// Remote: one task, strictly ordered updateWorkout, deleteExercises, insertExercises,
    /// insertSet...; on the first failure that step and all later ones are queued in order
    /// (the queue replays deleteExercises before inserts; see OfflineQueueManager.flush).
    func replaceWorkoutContents(_ workout: Workout, exercises: [Exercise], sets: [UUID: [WorkoutSet]]) {
        localStorage.updateWorkout(workout)
        localStorage.deleteExercises(workoutId: workout.id)
        localStorage.saveExercises(exercises, workoutId: workout.id)
        for exercise in exercises {
            for set in sets[exercise.id] ?? [] {
                localStorage.saveSet(set, exerciseId: exercise.id)
            }
        }

        let orderedSets = exercises.flatMap { sets[$0.id] ?? [] }
        Task {
            var failed = false

            do { try await supabaseService.updateWorkout(workout) } catch {
                failed = true
                await offlineQueueManager.enqueue(.updateWorkout, payload: workout)
            }

            if failed {
                await offlineQueueManager.enqueueDeleteExercises(workoutId: workout.id)
            } else {
                do { try await supabaseService.deleteExercises(workoutId: workout.id) } catch {
                    failed = true
                    await offlineQueueManager.enqueueDeleteExercises(workoutId: workout.id)
                }
            }

            if !exercises.isEmpty {
                if failed {
                    await offlineQueueManager.enqueue(.insertExercises, payload: exercises)
                } else {
                    do { try await supabaseService.insertExercises(exercises) } catch {
                        failed = true
                        await offlineQueueManager.enqueue(.insertExercises, payload: exercises)
                    }
                }
            }

            for set in orderedSets {
                if failed {
                    await offlineQueueManager.enqueue(.insertSet, payload: set)
                } else {
                    do { try await supabaseService.insertSet(set) } catch {
                        failed = true
                        await offlineQueueManager.enqueue(.insertSet, payload: set)
                    }
                }
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
                await offlineQueueManager.enqueue(.updateWorkout, payload: workout)
            }
        }
    }

    func updateSet(_ workoutSet: WorkoutSet) {
        localStorage.updateSet(workoutSet)
        // Note: Supabase doesn't have an updateSet method, PR flag is saved on initial insert
    }

    // MARK: - Streak

    func fetchStreak(userId: UUID) -> Int {
        localStorage.countConsecutiveWorkoutDays(userId: userId)
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

    // MARK: - Delete

    func deleteExercise(_ exerciseId: UUID) {
        localStorage.deleteExercise(exerciseId: exerciseId)
        Task {
            do {
                try await supabaseService.deleteExercise(id: exerciseId)
            } catch {
                await offlineQueueManager.enqueue(.deleteExercise, payload: DeleteExercisePayload(exerciseId: exerciseId))
            }
        }
    }

    func deleteExercises(forWorkoutId workoutId: UUID) {
        localStorage.deleteExercises(workoutId: workoutId)
        Task {
            do {
                try await supabaseService.deleteExercises(workoutId: workoutId)
            } catch {
                // Non-critical: local delete succeeded; Supabase will reconcile on next sync
            }
        }
    }

    func deleteSet(_ workoutSet: WorkoutSet) {
        localStorage.deleteSet(setId: workoutSet.id)
        Task {
            do {
                try await supabaseService.deleteSet(setId: workoutSet.id)
            } catch {
                await offlineQueueManager.enqueue(.deleteSet, payload: workoutSet)
            }
        }
    }

    func deleteWorkout(_ workout: Workout) {
        localStorage.deleteWorkout(workoutId: workout.id)
        Task {
            do {
                try await supabaseService.deleteWorkout(workoutId: workout.id)
            } catch {
                await offlineQueueManager.enqueue(.deleteWorkout, payload: workout)
            }
        }
    }
}
