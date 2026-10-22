import Foundation

/// Coordinates local + remote workout data access.
/// Reads from Core Data for instant display. Writes go to Core Data first, then
/// to Supabase exclusively through the offline queue (outbox-first).
final class WorkoutRepository {

    private let localStorage: LocalStorageService
    private let offlineQueueManager: OfflineQueueManager

    init(
        localStorage: LocalStorageService,
        offlineQueueManager: OfflineQueueManager
    ) {
        self.localStorage = localStorage
        self.offlineQueueManager = offlineQueueManager
    }

    // MARK: - Fetch

    func fetchTodayWorkout(userId: UUID) -> Workout? {
        let cdWorkouts = localStorage.fetchWorkoutsForDate(userId: userId, date: Date())
        return cdWorkouts.first.map { Workout(from: $0) }
    }

    func fetchWorkout(id: UUID) -> Workout? {
        localStorage.fetchWorkout(id: id).map { Workout(from: $0) }
    }

    func fetchRecentWorkouts(userId: UUID, limit: Int) -> [Workout] {
        localStorage.fetchRecentWorkouts(userId: userId, limit: limit)
            .map { Workout(from: $0) }
    }

    /// Real sessions only (at least one logged set). Never-started generated plans are excluded.
    func fetchRecentLoggedWorkouts(userId: UUID, limit: Int) -> [Workout] {
        localStorage.fetchRecentLoggedWorkouts(userId: userId, limit: limit)
            .map { Workout(from: $0) }
    }

    /// Distinct exercise names the user has done before, most recently used first.
    func fetchDistinctExerciseNames(userId: UUID) -> [HistoryExercise] {
        HistoryExercise.distinct(localStorage.fetchExerciseHistory(userId: userId))
    }

    // MARK: - Create / Save

    // Every write is: save locally, then hand the cloud write to the offline queue
    // (`submit` numbers it synchronously, so replay keeps the order of these calls).

    func createWorkout(_ workout: Workout) {
        localStorage.saveWorkout(workout)
        offlineQueueManager.submit(.insertWorkout, payload: workout, recordKey: workout.id.uuidString)
    }

    func saveExercises(_ exercises: [Exercise], workoutId: UUID) {
        localStorage.saveExercises(exercises, workoutId: workoutId)
        guard !exercises.isEmpty else { return }
        offlineQueueManager.submit(.insertExercises, payload: exercises)
    }

    func saveSet(_ workoutSet: WorkoutSet, exerciseId: UUID) {
        localStorage.saveSet(workoutSet, exerciseId: exerciseId)
        offlineQueueManager.submit(.insertSet, payload: workoutSet, recordKey: workoutSet.id.uuidString)
    }

    /// Saves a fully-formed past workout: everything locally, then queued in
    /// parent-first order (workout, exercises, sets).
    func importWorkout(_ workout: Workout, exercises: [Exercise], sets: [UUID: [WorkoutSet]]) {
        localStorage.saveWorkout(workout)
        localStorage.saveExercises(exercises, workoutId: workout.id)
        for exercise in exercises {
            for set in sets[exercise.id] ?? [] {
                localStorage.saveSet(set, exerciseId: exercise.id)
            }
        }

        offlineQueueManager.submit(.insertWorkout, payload: workout, recordKey: workout.id.uuidString)
        if !exercises.isEmpty {
            offlineQueueManager.submit(.insertExercises, payload: exercises)
        }
        for set in exercises.flatMap({ sets[$0.id] ?? [] }) {
            offlineQueueManager.submit(.insertSet, payload: set, recordKey: set.id.uuidString)
        }
    }

    /// Replaces a workout's header, exercises and sets (used by editing past workouts).
    /// Local: update workout, delete old exercises (sets cascade), save new exercises/sets.
    /// Queue: updateWorkout, deleteExercises, insertExercises, insertSet... in that causal
    /// order (the queue replays deleteExercises before inserts). Old exercises/sets that
    /// are not part of the new content get tombstones.
    func replaceWorkoutContents(_ workout: Workout, exercises: [Exercise], sets: [UUID: [WorkoutSet]]) {
        let old = descendantIds(ofWorkout: workout.id)
        localStorage.updateWorkout(workout)
        localStorage.deleteExercises(workoutId: workout.id)
        localStorage.saveExercises(exercises, workoutId: workout.id)
        let orderedSets = exercises.flatMap { sets[$0.id] ?? [] }
        for exercise in exercises {
            for set in sets[exercise.id] ?? [] {
                localStorage.saveSet(set, exerciseId: exercise.id)
            }
        }

        offlineQueueManager.submit(.updateWorkout, payload: workout, recordKey: workout.id.uuidString)
        offlineQueueManager.submitDeleteExercises(workoutId: workout.id)
        let keptExercises = Set(exercises.map(\.id))
        let keptSets = Set(orderedSets.map(\.id))
        offlineQueueManager.submitTombstones(.exercise, ids: old.exercises.filter { !keptExercises.contains($0) })
        offlineQueueManager.submitTombstones(.set, ids: old.sets.filter { !keptSets.contains($0) })
        if !exercises.isEmpty {
            offlineQueueManager.submit(.insertExercises, payload: exercises)
        }
        for set in orderedSets {
            offlineQueueManager.submit(.insertSet, payload: set, recordKey: set.id.uuidString)
        }
    }

    // MARK: - Update

    func updateWorkout(_ workout: Workout) {
        localStorage.updateWorkout(workout)
        offlineQueueManager.submit(.updateWorkout, payload: workout, recordKey: workout.id.uuidString)
    }

    /// Saves a changed set (e.g. the PR flag). The cloud write is an upsert of the same
    /// row, replacing a still-queued insert of it, so the final state is what uploads.
    func updateSet(_ workoutSet: WorkoutSet) {
        localStorage.updateSet(workoutSet)
        offlineQueueManager.submit(.insertSet, payload: workoutSet, recordKey: workoutSet.id.uuidString)
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

    // Each delete queues the remote delete AND a tombstone per removed record. Ids are
    // read locally BEFORE the local delete, because afterwards they are gone.

    func deleteExercise(_ exerciseId: UUID) {
        let setIds = localStorage.fetchSets(exerciseId: exerciseId).compactMap(\.id)
        localStorage.deleteExercise(exerciseId: exerciseId)
        offlineQueueManager.submit(.deleteExercise, payload: DeleteExercisePayload(exerciseId: exerciseId))
        offlineQueueManager.submitTombstones(.exercise, ids: [exerciseId])
        offlineQueueManager.submitTombstones(.set, ids: setIds)
    }

    func deleteExercises(forWorkoutId workoutId: UUID) {
        let old = descendantIds(ofWorkout: workoutId)
        localStorage.deleteExercises(workoutId: workoutId)
        offlineQueueManager.submitDeleteExercises(workoutId: workoutId)
        offlineQueueManager.submitTombstones(.exercise, ids: old.exercises)
        offlineQueueManager.submitTombstones(.set, ids: old.sets)
    }

    func deleteSet(_ workoutSet: WorkoutSet) {
        localStorage.deleteSet(setId: workoutSet.id)
        offlineQueueManager.submit(.deleteSet, payload: workoutSet)
        offlineQueueManager.submitTombstones(.set, ids: [workoutSet.id])
    }

    func deleteWorkout(_ workout: Workout) {
        let old = descendantIds(ofWorkout: workout.id)
        localStorage.deleteWorkout(workoutId: workout.id)
        offlineQueueManager.submit(.deleteWorkout, payload: workout)
        offlineQueueManager.submitTombstones(.workout, ids: [workout.id])
        offlineQueueManager.submitTombstones(.exercise, ids: old.exercises)
        offlineQueueManager.submitTombstones(.set, ids: old.sets)
    }

    /// Ids of a workout's exercises and their sets, as stored locally right now.
    private func descendantIds(ofWorkout workoutId: UUID) -> (exercises: [UUID], sets: [UUID]) {
        var exerciseIds: [UUID] = []
        var setIds: [UUID] = []
        for exercise in localStorage.fetchExercises(workoutId: workoutId) {
            guard let exerciseId = exercise.id else { continue }
            exerciseIds.append(exerciseId)
            setIds.append(contentsOf: localStorage.fetchSets(exerciseId: exerciseId).compactMap(\.id))
        }
        return (exerciseIds, setIds)
    }
}
