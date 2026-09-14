import Foundation

/// Manages history state: fetching past workouts, pagination,
/// and filtering by workout type.
final class HistoryViewModel: ObservableObject {

    @Published var workouts: [Workout] = []
    @Published var filterType: String? = nil
    @Published var isLoading: Bool = false
    @Published private(set) var allWorkouts: [Workout] = []

    private let workoutRepository: WorkoutRepository
    private let prRepository: PRRepository

    init(workoutRepository: WorkoutRepository, prRepository: PRRepository) {
        self.workoutRepository = workoutRepository
        self.prRepository = prRepository
    }

    // MARK: - Load Workouts

    func loadWorkouts(userId: UUID) {
        isLoading = true
        let fetched = workoutRepository.fetchRecentWorkouts(userId: userId, limit: 200)
        allWorkouts = fetched
        workouts = Self.filtered(fetched, by: filterType)
        isLoading = false
    }

    // MARK: - Filter

    func setFilter(_ type: String?, userId: UUID) {
        filterType = type
        loadWorkouts(userId: userId)
    }

    var availableTypes: [String] {
        Self.availableTypes(in: allWorkouts)
    }

    /// Returns the workouts matching `type` (case-insensitive comparison against
    /// `workoutType`), or all workouts if `type` is nil.
    static func filtered(_ workouts: [Workout], by type: String?) -> [Workout] {
        guard let filter = type else { return workouts }
        return workouts.filter { $0.workoutType.lowercased() == filter.lowercased() }
    }

    /// Returns the unique workout types present in `workouts`, sorted alphabetically.
    static func availableTypes(in workouts: [Workout]) -> [String] {
        let types = Set(workouts.map { $0.workoutType })
        return types.sorted()
    }

    // MARK: - Workout Summary

    func workoutSummary(_ workout: Workout) -> (exerciseCount: Int, totalVolume: Double) {
        let exercises = fetchExercises(workoutId: workout.id)
        var totalVolume = 0.0

        for exercise in exercises {
            let sets = fetchSets(exerciseId: exercise.id)
            for set in sets {
                totalVolume += set.weightLbs * Double(set.reps)
            }
        }

        return (exerciseCount: exercises.count, totalVolume: totalVolume)
    }

    // MARK: - Fetch Helpers

    func fetchExercises(workoutId: UUID) -> [Exercise] {
        workoutRepository.fetchExercises(workoutId: workoutId)
    }

    func fetchSets(exerciseId: UUID) -> [WorkoutSet] {
        workoutRepository.fetchSets(exerciseId: exerciseId)
    }

    // MARK: - Delete

    func deleteWorkout(_ workout: Workout, userId: UUID) {
        // Capture exercise names before cascade delete removes them
        let exerciseNames = workoutRepository.fetchExercises(workoutId: workout.id).map { $0.name }

        workoutRepository.deleteWorkout(workout)
        workouts.removeAll { $0.id == workout.id }
        allWorkouts.removeAll { $0.id == workout.id }

        // Recalculate PRs for every exercise in the deleted workout
        for name in exerciseNames {
            prRepository.recalculatePR(userId: userId, exerciseName: name)
        }
    }
}
