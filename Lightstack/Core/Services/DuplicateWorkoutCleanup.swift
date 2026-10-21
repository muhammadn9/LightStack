import Foundation

/// Finds and removes exact-duplicate workouts: same user, same day, same type and an identical
/// multiset of logged sets (exercise name, weight, reps, RIR; cardio duration/distance too).
/// Anything that is not an exact duplicate is left alone. The earliest created copy is kept and
/// the others go through `WorkoutRepository.deleteWorkout`, so the cloud delete and tombstones
/// are queued and a restore cannot resurrect them. PRs of the affected exercises are rebuilt.
final class DuplicateWorkoutCleanup {

    private let localStorage: LocalStorageService
    private let workoutRepository: WorkoutRepository
    private let prRepository: PRRepository

    init(localStorage: LocalStorageService, workoutRepository: WorkoutRepository, prRepository: PRRepository) {
        self.localStorage = localStorage
        self.workoutRepository = workoutRepository
        self.prRepository = prRepository
    }

    /// Returns the number of duplicate workouts removed.
    /// `protecting`: workout ids that must never be deleted (the one being logged right now).
    @discardableResult
    func removeExactDuplicates(userId: UUID, protecting: Set<UUID> = []) -> Int {
        let duplicates = findDuplicates(userId: userId, protecting: protecting)
        var affectedNames = Set<String>()
        for workout in duplicates {
            for exercise in workoutRepository.fetchExercises(workoutId: workout.id) { affectedNames.insert(exercise.name) }
            workoutRepository.deleteWorkout(workout)
        }
        for name in affectedNames.sorted() {
            prRepository.recalculatePR(userId: userId, exerciseName: name)
        }
        return duplicates.count
    }

    /// The workouts to delete: every non-earliest member of each group of identical workouts.
    func findDuplicates(userId: UUID, protecting: Set<UUID> = []) -> [Workout] {
        let calendar = Calendar.current
        var groups: [String: [CDWorkout]] = [:]
        for cd in localStorage.fetchAllWorkouts(userId: userId) {
            guard let signature = Self.setSignature(of: cd), !signature.isEmpty, let date = cd.date else { continue }
            let type = (cd.workoutType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let day = calendar.startOfDay(for: date).timeIntervalSince1970
            groups["\(day)|\(type)|\(signature.joined(separator: ";"))", default: []].append(cd)
        }

        var result: [Workout] = []
        for (_, members) in groups where members.count > 1 {
            let ordered = members.sorted { a, b in
                let ca = a.createdAt ?? .distantFuture, cb = b.createdAt ?? .distantFuture
                if ca != cb { return ca < cb }
                return (a.id?.uuidString ?? "") < (b.id?.uuidString ?? "")
            }
            // Keep the earliest; a protected (live) copy is never deleted either.
            for cd in ordered.dropFirst() {
                guard let id = cd.id, !protecting.contains(id) else { continue }
                result.append(Workout(from: cd))
            }
        }
        return result
    }

    /// Sorted description of every logged set, or nil if there are none.
    static func setSignature(of workout: CDWorkout) -> [String]? {
        var parts: [String] = []
        for exercise in workout.exercises as? Set<CDExercise> ?? [] {
            let name = exercise.name ?? ""
            for set in exercise.sets as? Set<CDWorkoutSet> ?? [] {
                let weight = String(format: "%.3f", set.weightLbs)
                let duration = set.durationSeconds?.intValue ?? -1
                let distance = set.distanceMiles.map { String(format: "%.3f", $0.doubleValue) } ?? "-"
                parts.append("\(name)|\(weight)|\(set.reps)|\(set.rir)|\(duration)|\(distance)")
            }
        }
        return parts.sorted()
    }
}
