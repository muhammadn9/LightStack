import Foundation

/// Manages history state: fetching past workouts, pagination,
/// and filtering by workout type.
final class HistoryViewModel: ObservableObject {

    @Published var workouts: [Workout] = []
    @Published var filterType: String? = nil
    @Published var isLoading: Bool = false

    private let workoutRepository: WorkoutRepository

    init(workoutRepository: WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    // MARK: - Load Workouts

    func loadWorkouts(userId: UUID) {
        isLoading = true
        let allWorkouts = workoutRepository.fetchRecentWorkouts(userId: userId, limit: 200)

        if let filter = filterType {
            workouts = allWorkouts.filter { $0.workoutType.lowercased() == filter.lowercased() }
        } else {
            workouts = allWorkouts
        }

        isLoading = false
    }

    // MARK: - Filter

    func setFilter(_ type: String?, userId: UUID) {
        filterType = type
        loadWorkouts(userId: userId)
    }

    var availableTypes: [String] {
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
}
